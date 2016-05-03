class SendmailParser
  def initialize(conf)
    @base_regexp = /^(?<time>\w+\s+\w+\s+\d+:\d+:\d+) (?<host>[^ ]+) (?<procowner>[^\[]+)\[(?<procid>\d+)\]: (?<qid>[^ ]+): (?<entry>(?<type>[^=]+).+)$/;
  end

  def parse(value)
    m = @base_regexp.match(value)
    unless m
      # $log.warn "sendmail: pattern not match: #{value.inspect}"
      return nil
    end

    logtype = m["type"]
    entry = m["entry"]
    mta = m["host"]
    qid = m["qid"]
    time = Time.parse(m["time"]).to_i || Fluent::Engine.now.to_i

    logline = {
      "type" => :from,
      "mta" => mta,
      "qid" => qid,
      "time" => time,
      "type" => nil,
      "noncommon" => nil
    }

    case logtype
    when "from"
      fromline = self.from_parser(entry)
      logline["type"] = :from
      logline["noncommon"] = fromline
    when "to"
      toline = self.to_parser(entry)
      logline["type"] = :to
      logline["noncommon"] = toline
    else
      # not match
      logline =  nil
    end

    logline
  end

  def to_line(entry)
    record = {}
    status = nil

    status = status_parser(entry)

    entry.split(", ").each {|param|
      key, val = param.split("=")
      record[key] = val
    }
    record["to"] = record["to"].split(",")

    if record.has_key?("relay")
      record["relay"] = relay_parser(record["relay"])
    end
    ToLine.new(status, record)
  end

  def from_line(entry)
    record = {}

    entry.split(", ").each {|param|
      key, val = param.split("=")
      record[key] = val
    }
    if record.has_key?("relay")
      record["relay"] = relay_parser(record["relay"])
    end
    FromLine.new(record)
  end

  def to_parser(entry)
    to_line(entry)
  end

  def from_parser(entry)
    from_line(entry)
  end

  def relay_parser(relays)
    relay_host = nil
    relay_ip   = nil
    relays.split(" ").each {|relay|
      if relay.index("[") == 0
        return {"ip" => trim_bracket(relay), "host" => relay_host}
      else
        relay_host = relay
      end
    }
    return {"ip" => relay_ip, "host" => relay_host}
  end

  def trim_bracket(val)
    val[1..-2]
  end

  def status_parser(entry)
    if entry.include?("stat=Sent")
      return :sent
    elsif entry.include?("dsn=5.")
      return :bounced
    elsif entry.include?("stat=Deferred")
      return :deferred
    else
      return :other
    end
  end
end

class FromLine
  attr_reader :record
  def initialize(record)
    @record = record
  end
end

class ToLine
  attr_reader :status
  attr_reader :record
  def initialize(status, record)
    @status = status
    @record = record
  end
end
