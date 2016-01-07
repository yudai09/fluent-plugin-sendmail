class Fluent::SendmailInput < Fluent::TailInput
  config_param :lrucache_size, :integer, :default => (1024*1024)
  
  Fluent::Plugin.register_input('sendmail', self)

  require_relative 'sendmailparser'
  require 'pathname'
  require 'lru_redux'

  config_param :types, :string, :default => 'from,sent'

  def initialize
    super
    @transactions = LruRedux::ThreadSafeCache.new(@lrucache_size)
  end

  def configure_parser(conf)
    @parser = SendmailParser.new(conf)
  end

  def receive_lines(lines)
    es = Fluent::MultiEventStream.new
    lines.each {|line|
      begin
        line.chomp!  # remove \n
        mta, qid, type, time, record = parse_line(line)

        if mta && qid && type && time && record
          # make recordid uniq even if multiple MTA's log are mixed. 
          recordid = mta + qid
          if @transactions.has_key?(recordid)
            @transactions[recordid].merge(type, time, record)
            if @transactions[recordid].status == :ready
              log = @transactions[recordid]
              es.add(log.time, log.record)
              @transactions.delete(qid)
              # log.destroy
            end
          # new log
          elsif mta && qid && type == :from && time && record
            recordid = mta + qid
            @transactions[recordid] = SendmailLog.new(mta, time, record)
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
end

class SendmailLog
  attr_reader :status
  attr_reader :time
  def initialize(mta, time, record)
    @mta = mta
    @status = :init
    @time = time
    @tos  = {}
    @from = record
    @count = record["nrcpts"].to_i
  end

  def record
    return {
      "mta" => @mta,
      "from" => @from["from"],
      "relay" => @from["relay"],
      "count" => @from["nrcpts"],
      "size" => @from["size"],
      "msgid" => @from["msgid"],
      "popid" => @from["popid"],
      "authid" => @from["authid"],
      "to" => @tos.map {|name, to|
        {
          "to" => to["to"],
          "relay" => to["relay"],
          "stat" => to["stat"],
          "dsn" => to["dsn"],
          "delay" => to["delay"],
          "xdelay" => to["xdelay"]
        }
      }
    }
  end

  def merge(type, time, record)
    if type == :sent
      @count = @count - record["to"].size
      @tos[record["relay"]["ip"]] = record
      if @count == 0
        @status = :ready
      end
    end
  end
end
