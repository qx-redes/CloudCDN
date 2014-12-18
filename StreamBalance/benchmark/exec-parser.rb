#!/usr/bin/ruby
cmd = "#{ARGV[0]} #{ARGV[1]} #{ARGV[2]} #{ARGV[3]} 2>&1 | grep \"PLAY Response Code\" > /tmp/resultado/#{Process.pid} &"
exec cmd
