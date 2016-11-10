class SendmailParser
  def initialize(conf)
    @base_regexp = /^(?<time>\w+\s+\w+\s+\d+:\d+:\d+) (?<mta>[^ ]+) (?<procowner>[^\[]+)\[(?<procid>\d+)\]: (?<qid>[^ ]+): (?<entry>(?<type>[^=]+).+)$/;
  end

  def parse(value)
    m = @base_regexp.match(value)
    unless m
      # $log.warn "sendmail: pattern not match: #{value.inspect}"
      return nil
    end
    time = Time.parse(m["time"]).to_i || Fluent::Engine.now.to_i
    record = {
      "time" => time,
      "mta" => m["mta"],
      "qid" => m["qid"],
      "type" => m["type"],
    }
    case m["type"]
    when "from"
      fromline = self.from_line(m["entry"])
      record.merge!(fromline)
    when "to"
      toline = self.to_line(m["entry"])
      record.merge!(toline)
    else # not match
      m =  nil
    end
    record
  end

  def to_line(entry)
    record = {}
    status = nil
    record["status_canonical"] = status_parser(entry)
    entry.split(", ").each {|param|
      key, val = param.split("=")
      record[key] = val
    }
    record["to"] = record["to"].split(",")
    if record.has_key?("relay")
      record["relay"] = relay_parser(record["relay"])
    end
    record["delay_in_sec"] = delay_parser(record["delay"])
    return record
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
    return record
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

  def status_parser(entry)
    if entry.include?("stat=Sent")
      if entry.include?("mailer=local,")
        return "sent_local"
      else
        return "sent"
      end
    elsif entry.include?("dsn=5.")
      return "bounced"
    elsif entry.include?("stat=Deferred")
      return "deferred"
    else
      return "other"
    end
  end

  def delay_parser(delay)
    /((?<day>[0-9]*)\+)?(?<hms>[0-9]{2,2}:[0-9]{2,2}:[0-9]{2,2})/ =~ delay
    day = day.to_i
    dtime = Time.parse(hms)
    delay = (day * 24 * 60 * 60) + (dtime.hour * 60 * 60) + (dtime.min * 60) + (dtime.sec)
  end

  def trim_bracket(val)
    val[1..-2]
  end
end
