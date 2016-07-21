# -*- coding: utf-8 -*-
class Fluent::SendmailInput < Fluent::TailInput
  config_param :lrucache_size, :integer, :default => (1024*1024)

  Fluent::Plugin.register_input('sendmail', self)

  require_relative 'sendmailparser'
  require 'pathname'
  require 'lru_redux'

  config_param :types, :string, :default => 'from,sent'
  config_param :unbundle, :string, :default => 'no'
  # sendmail default value of queuereturn is 5d (432000sec)
  config_param :queuereturn, :time, :default => 432000

  def initialize
    super
    @delivers = LruRedux::ThreadSafeCache.new(@lrucache_size)
  end

  def configure_parser(conf)
    @parser = SendmailParser.new(conf)
    if @unbundle == 'yes'
      @do_unbundle = true
    else
      @do_unbundle = false
    end
  end

  def receive_lines(lines)
    es = Fluent::MultiEventStream.new
    lines.each {|line|
      begin
        line.chomp!  # remove \n
        logline = parse_line(line)

        if logline.nil?
          next
        end

        type   = logline["type"]
        mta    = logline["mta"]
        qid    = logline["qid"]
        time   = logline["time"]
        # a qid is not uniq worldwide.
        # make delivery id uniq even if multiple MTA's log are mixed. 
        deliveryid = mta + qid
        type   = logline["type"]
        noncommon = logline["noncommon"]

        case type
        when :from
          # new log
          from = noncommon
          record = from.record
          if @delivers.has_key?(deliveryid)
            $log.warn "duplicate sender line found. " + line.dump
          else
            @delivers[deliveryid] = SendmailLog.new(mta, time, record)
          end
        when :to
          to = noncommon
          status = to.status
          record = noncommon.record
          if @delivers.has_key?(deliveryid)
            to = noncommon
            status = to.status
            case status
            when :sent, :sent_local, :bounced
              sent(es, deliveryid, time, record)
            when :deferred
              queued(es, deliveryid, time, record)
            when :other
              $log.warn "cannot find this kind of delivery status: " + line.dump
            end
          else
            # cannot find any 'from' line corresponded to the 'to' line
          end
        end
      rescue
        $log.warn line.dump, :error=>$!.to_s
        raise
      end
    }

    unless es.empty?
      begin
        Fluent::Engine.emit_stream(@tag, es)
      rescue
        # ignore errors. Engine shows logs and backtraces.
        raise
      end
    end
  end

  def sent(es, deliveryid, time, record)
    @delivers[deliveryid].done(time, record)
    if @do_unbundle
      log_single(es, deliveryid, time, record)
    end
    # bulked queue in an attempt have been dequeued completely.
    if @delivers[deliveryid].status == :all_done
      # bundled logs are outputed here
      if not @do_unbundle
        log_bundled(es, deliveryid, time)
      end
      # log.destroy
      @delivers.delete(deliveryid)
    end
  end

  def queued(es, deliveryid, time, record)
    # when a queue is expired, the mail will be bounced
    delay = delay2sec(record["delay"])
    if delay >= queuereturn
    # if false
      record["canonical_status"] = 'bounced'
      sent(es, deliveryid, time, record)
      return
    end
    if @do_unbundle
      log_single(es, deliveryid, time, record)
    end
  end

  def delay2sec(delay_str)
    /((?<day>[0-9]*)\+)?(?<hms>[0-9]{2,2}:[0-9]{2,2}:[0-9]{2,2})/ =~ delay_str
    day = day.to_i
    dtime = Time.parse(hms)
    delay = (day * 60 * 60 * 60) + (dtime.hour * 60 * 60) + (dtime.min * 60) + (dtime.sec)

  end

  def log_single(es, deliveryid, time, record)
    log = @delivers[deliveryid]
    records = log.record_unbundle(time, record)
    for record in records do
      es.add(time, record)
    end
  end

  def log_bundled(es, deliveryid, time)
    log = @delivers[deliveryid]
    es.add(time, log.record)
  end

end

class SendmailLog
  attr_reader :status
  attr_reader :time
  def initialize(mta, time, record)
    @mta = mta
    @status = :init
    @time = time
    @tos  = []
    @from = record
    @count = record["nrcpts"].to_i
  end

  def record
    return {
      "mta" => @mta,
      "from" => @from,
      "to" => @tos
    }
  end

  def record_unbundle(time, record)
    records_unbundled = []
    for to in record["to"] do
      record_single = record.dup
      record_single["to"] = to
      records_unbundled.push({
        "mta" => @mta,
        "from" => @from,
        "to" => record_single
      })
    end
    return records_unbundled
  end

  def done(time, record)
    @count = @count - record["to"].size
    @tos.push(record)
    if @count == 0
      @status = :all_done
    end
  end
end
