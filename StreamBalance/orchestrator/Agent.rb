#!/usr/bin/env ruby
require 'System'
module UFC
  #Inicia serviço
  DRb.start_service 'druby://0.0.0.0:9000', Coletor.new
  puts "Serviço iniciado em #{DRb.uri}"
  DRb.thread.join
end

