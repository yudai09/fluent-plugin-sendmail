# Fluent::Plugin::Sendmail

Fluentd plugin to merge sender line and receiver line into one json data.

## Configuration

```
<source>
  type sendmail
  path /var/log/maillog
  tag sendmail
  queuereturn 60m
  path_cache_file /tmp/test.dat
</source>
```

example of sendmail log

```
Apr  2 00:15:25 mta001 sendmail[32300]: u31FFPtp032300: Milter: no active filter
Apr  2 00:15:25 mta001 sendmail[32300]: u31FFPtp032300: from=<grandeur09@gmail.com>, size=5938, class=0, nrcpts=5, msgid=<201604011515.u31FFIAj012911@gmail.com>, proto=ESMTP, daemon=MTA, relay=[64.233.187.27]
Apr  2 00:15:25 mta001 sendmail[32302]: u31FFPtp032300: SMTP outgoing connect on [192.168.198.81]
Apr  2 00:15:25 mta001 sendmail[32302]: u31FFPtp032300: to=<sent1@example.com>,<sent2@example.com>, 00:00:00, xdelay=00:00:00, mailer=esmtp, pri=245938, relay=[93.184.216.34] [93.184.216.34], dsn=2.0.0, stat=Sent (ok:  Message 40279894 accepted)
Apr  2 00:15:25 mta001 sendmail[12566]: u31FFPtp032300: to=<deferred1@example.com>, delay=00:00:15, xdelay=00:00:15, mailer=esmtp, pri=34527, relay=[93.184.216.34] [93.184.216.34], dsn=4.3.5, stat=Deferred: 451 4.3.5 Server configuration problem
Apr  2 00:15:26 mta001 sendmail[32302]: u31FFPtp032300: to=<sent3@example2.com>,<sent4@example2.com>, delay=00:00:00, xdelay=00:00:00, mailer=esmtp, pri=245938, relay=[93.184.216.34] [93.184.216.34], dsn=2.0.0, stat=Sent (ok:  Message 40279895 accepted)
Apr  2 00:18:50 mta001 sendmail[32302]: u31FFPtp032300: to=<deferred1@example.com>, delay=00:00:00, xdelay=00:00:00, mailer=esmtp, pri=245938, relay=[93.184.216.34] [93.184.216.34], dsn=2.0.0, stat=Sent (ok:  Message 40279894 accepted)
Apr  2 00:15:25 mta001 sendmail[32302]: u31FFPtp032300: done; delay=00:00:00, ntries=2
```

This plugin emit record like below:

```
2014-01-10 01:00:01 +0900 sendmail:
{
    "time":1459523725,
    "mta":"mta001",
    "qid":"u31FFPtp032300",
    "from":"<grandeur09@gmail.com>",
    "size":"5938",
    "class":"0",
    "nrcpts":"7",
    "msgid":"<201604011515.u31FFIAj012911@gmail.com>",
    "proto":"ESMTP",
    "daemon":"MTA",
    "relay":{
        "ip":"93.184.216.34",
        "host":null
    },
    "status_canonical":"sent",
    "to":[
        "<sent1@example.com>",
        "<sent2@example.com>"
    ],
    "delay":"00:00:00",
    "xdelay":"00:00:00",
    "mailer":"esmtp",
    "pri":"245938",
    "dsn":"2.0.0",
    "stat":"Sent (ok: Message 40279894 accepted)",
    "delay_in_sec":0
}
```

## TODO

write test for path_cache_file parmeter

## ChangeLog

See [CHANGELOG.md](CHANGELOG.md) for details.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Copyright

Copyright (c) 2014 muddydixon. See [LICENSE](LICENSE) for details.
