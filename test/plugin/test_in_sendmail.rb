require 'helper'
require 'json'

class SendmailInputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
    log = Fluent::Engine.log
  end

  TMP_DIR = File.dirname(__FILE__) + "/../tmp"
  DATA_DIR = File.dirname(__FILE__) + "/../data"

  CONFIG = %[
    path #{TMP_DIR}/sendmaillog
    tag sendmail
    queuereturn 1d
    path_cache_file /tmp/fluent_plugin_sendmail_test_cache_file
  ]

  def setup
    Fluent::Test.setup
    FileUtils.rm_rf(TMP_DIR)
    FileUtils.mkdir_p(TMP_DIR)
  end

  def create_driver(conf = CONFIG, tag='test')
    driver = Fluent::Test::InputTestDriver.new(Fluent::SendmailInput)
    driver.configure(conf)
    driver
  end

  def test_configure
  end

  def test
    data_file = "#{DATA_DIR}/data"
    expect_file = "#{DATA_DIR}/result"
    driver = create_driver(conf=CONFIG)
    do_test(driver, data_file, expect_file)
  end

  def do_test(driver, data_file, expect_file)
    lines = nil
    path = driver.instance.paths[0].to_s

    # touch tail file
    File.open(path, "a") {}
    # result_expect
    expects = []

    File.open(expect_file, "r") {|expectfile|
      expectfile.each_line {|line|
        expects.push(JSON.parse(line))
      }
    }

    driver.run do
      sleep 1
      File.open(data_file, "r") {|srcfile|
        File.open(path, "a") {|dstfile|
          srcfile.each_line {|line|
            dstfile.puts(line)
          }
        }
      }
      sleep 1
    end

    emits = driver.emits
    assert(emits.length > 0, "no emits")

    emits.each_index {|i|
      assert_equal(expects[i], emits[i][2])
    }

  end
end
