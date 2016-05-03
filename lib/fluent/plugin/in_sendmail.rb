# -*- coding: utf-8 -*-
class Fluent::SendmailInput < Fluent::TailInput
  config_param :lrucache_size, :integer, :default => (1024*1024)

  Fluent::Plugin.register_input('sendmail', self)

  require_relative 'sendmailparser'
  require 'pathname'
  require 'lru_redux'

  config_param :types, :string, :default => 'from,sent'
  config_param :unbundle, :string, :default => 'no'

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
          @delivers[deliveryid] = SendmailLog.new(mta, time, record)
        when :to
          to = noncommon
          status = to.status
          record = noncommon.record
          if @delivers.has_key?(deliveryid)
            to = noncommon
            status = to.status
            case status
            when :sent, :sent_local, :bounced
              @delivers[deliveryid].dequeued(time, record)
              if @do_unbundle
                log_single(es, deliveryid, time, record)
              end
              # bulked queue in an attempt have been dequeued completely.
              if @delivers[deliveryid].status == :all_dequeued
                # bundled logs are outputed here
                if not @do_unbundle
                  log_bundled(es, deliveryid, time)
                end
                # log.destroy
                @delivers.delete(qid)
              end
            when :deferred
              if @do_unbundle
                log_single(es, deliveryid, time, record)
              end
            when :other
              $log.warn "cannot find this kind of delivery status: " + line.dump
            end
          else
            # cannot find any 'from' line corresponded to the 'to' line
          end
        end
      rescue
        $log.warn line.dump, :error=>$!.to_s
        $log.debug_backtrace
      end
    }

    unless es.empty?
      begin
        Fluent::Engine.emit_stream(@tag, es)
      rescue
        # ignore errors. Engine shows logs and backtraces.
      end
    end
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

  def dequeued(time, record)
    @count = @count - record["to"].size
    @tos.push(record)
    if @count == 0
      @status = :all_dequeued
    end
  end
end
