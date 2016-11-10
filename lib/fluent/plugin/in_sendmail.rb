# -*- coding: utf-8 -*-
class Fluent::SendmailInput < Fluent::TailInput
  Fluent::Plugin.register_input("sendmail", self)

  config_param :lrucache_size, :integer, :default => (1024*1024)
  # sendmail default value of queuereturn is 5d (432000sec)
  config_param :queuereturn, :time, :default => 432000
  config_param :path_cache_file, :string, :default => nil

  require_relative "sendmailparser"
  require "lru_redux"

  def configure(conf)
    super
    @delivers = LruRedux::ThreadSafeCache.new(@lrucache_size)
    if @path_cache_file != nil
      if not File.exists?(@path_cache_file)
        File.open(@path_cache_file, "w+"){|cache_file|
          cache_file.puts('{}')
        }
      end
      if not File.readable?(@path_cache_file)
        raise ConfigError, "cache file exists but not readable."
      end
      if not File.writable?(@path_cache_file)
        raise Fluent::ConfigError, "cache file not writable."
      end
      File.open(@path_cache_file, "r") {|cache_file|
        line = cache_file.read()
        data = JSON.parse(line)
        data.each{|k, v|
          @delivers[k] = SendmailLog.new(v['time'], v['from_line'], v['nrcpts'])
        }
      }
    end
  end

  def configure_parser(conf)
    @parser = SendmailParser.new(conf)
  end

  def shutdown
    super
    if @path_cache_file != nil
      data = {}
      if @path_cache_file != nil
        @delivers.each{|k, v|
          data[k] = v.to_json
        }
      end
      File.open(@path_cache_file, "w+") {|cache_file|
        cache_file.puts(data)
      }
    end
  end

  def receive_lines(lines)
    es = Fluent::MultiEventStream.new
    lines.each {|line|
      begin
        line.chomp!  # remove \n
        record = parse_line(line)
        if record.nil?
          next
        end

        type   = record["type"]
        mta    = record["mta"]
        qid    = record["qid"]
        time   = record["time"]
        # a qid is not uniq worldwide.
        # make delivery id uniq even if multiple MTA"s log are mixed.
        deliveryid = mta + qid
        type   = record["type"]
        # remove unnecessary key `type"
        record.delete("type")

        case type
        when "from"
          # new log
          if @delivers.has_key?(deliveryid)
            $log.warn "duplicate sender line found. " + line.dump
          else
            @delivers[deliveryid] = SendmailLog.new(time, record)
          end
        when "to"
          if @delivers.has_key?(deliveryid)
            case record["status_canonical"]
            when "sent", "sent_local", "bounced"
              sent(es, deliveryid, time, record)
            when "deferred"
              queued(es, deliveryid, time, record)
            when "other"
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

  def sent(es, deliveryid, time, to_line)
    from_line = @delivers[deliveryid].from_line
    record = from_line.merge(to_line)
    es.add(time, record)
    nrcpts = @delivers[deliveryid].nrcpts
    @delivers[deliveryid].nrcpts -= to_line["to"].length
    # all done
    if @delivers[deliveryid].nrcpts <= 0
      @delivers.delete(deliveryid)
    end
  end

  def queued(es, deliveryid, time, to_line)
    from_line = @delivers[deliveryid].from_line
    record = from_line.merge(to_line)
    delay = to_line["delay_in_sec"]
    # when a queue is expired, the mail will be bounced
    if delay >= queuereturn
      record["canonical_status"] = "bounced"
      sent(es, deliveryid, time, record)
      return
    end
    record = from_line.merge(to_line)
    es.add(time, record)
  end
end

class SendmailLog
  attr_reader :time
  attr_reader :from_line
  attr_accessor :nrcpts

  def initialize(time, from_line, nrcpts=nil)
    @time = time
    @from_line = from_line
    if nrcpts == nil
      @nrcpts = from_line["nrcpts"].to_i
    else
      @nrcpts = nrcpts
    end
  end

  def to_json()
    return {
      "time" => @time,
      "from_line" => @from_line,
      "nrcpts" => @nrcpts,
    }
  end
end
