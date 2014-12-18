#!/usr/bin/env ruby
require "rubygems"
require 'moving_average'
require 'thread'
require 'logger'
require "xmlrpc/client"
require 'System'

  @listaDeMaquinas  = { "<IP1>" => nil, "<IP2>" => nil}
  @bandaMedia  = { "<IP1>" => 0, "<IP2>" => 0}
  @arp = { "<IP1>" => "<MAC1>", "<IP2>" => "<MAC2>"}
  @semaphore = Mutex.new
  @cooldown = Time.now
  @paused  = { "<IP1>" => nil, "<IP2>" => nil}
  @server = "<IP_LOAD_BALANCER>"
 
  def self.enable(ip) 
    Thread.new {
        sleep(10)
        @listaDeMaquinas[ip] = DRbObject.new nil, "druby://#{ip}:9000"
        server = XMLRPC::Client.new("<IP_LOAD_BALANCER>", "/RPC2", 8000)
	result = server.call("addServer", ip, @arp[ip])
	Log.escreve("Server #{ip} habilitado: #{result}")
    } 
    rescue Exception => e
       Log.escreve("Server #{ip} habilitado: #{result}")
       puts e.message  
       puts e.backtrace.inspect
  end

  def self.enableinicial(ip) 
    @listaDeMaquinas[ip] = DRbObject.new nil, "druby://#{ip}:9000"
    server = XMLRPC::Client.new("<IP_LOAD_BALANCER>", "/RPC2", 8000)
    result = server.call("addServer", ip, @arp[ip])
    Log.escreve("Server #{ip} habilitado: #{result}")
    rescue Exception => e
       Log.escreve("Server #{ip} habilitado: #{result}")
       puts e.message  
       puts e.backtrace.inspect
  end

  def self.disable(ip) 
    @listaDeMaquinas[ip] = nil
    server = XMLRPC::Client.new("<IP_LOAD_BALANCER>", "/RPC2", 8000)
    result = server.call("delServer", ip)
    Log.escreve("Server #{ip} desabilitado: #{result}")
    rescue Exception => e
	Log.escreve("Server #{ip} desabilitado: #{result}")
	puts e.message  
  	puts e.backtrace.inspect
  end

  def self.pause(ip)
    Log.escreve("Pausa (on): server #{ip}")
    @paused[ip] = true 
    server = XMLRPC::Client.new("<IP_LOAD_BALANCER>", "/RPC2", 8000)
    result = server.call("delServer", ip)
    Log.escreve("Server #{ip} pausado: #{result}")
    rescue Exception => e
	Log.escreve("Server #{ip} pausado: #{result}")
	puts e.message  
  	puts e.backtrace.inspect
  end

  def self.unpause(ip)
    Log.escreve("Pausa (off): server #{ip}")
    @paused[ip] = nil
    server = XMLRPC::Client.new("<IP_LOAD_BALANCER>", "/RPC2", 8000)
    result = server.call("addServer", ip, @arp[ip])
    Log.escreve("Server #{ip} despausado: #{result}")
    rescue Exception
	Log.escreve("Server #{ip} despausado: #{result}")
  end

  def self.qtdServerAtivos
    cont = 0
    soma = 0.0
    @listaDeMaquinas.each do |ip, c|
      if c != nil
        cont = cont + 1
        soma = soma + @bandaMedia[ip]
      end
    end
    return cont,soma
  end

  def self.qtdPausados
    cont = 0
    @paused.each do |ip, pausado|
      if pausado != nil
        cont = cont + 1
      end
    end
    return cont
  end

  def self.predict(server, dados)
    nums = Array.new
    pred = Array.new
    linhas = dados.split(/\n/)
    linhas.each do |line|
      nums << line.split(',')[2].to_f
    end
    (0..4).each do |i|
      pred[i] = nums.ema(i+4,5)
      nums << pred[i]
    end
    banda = (pred[0] + pred[1] + pred[2] + pred[3] + pred[4]) / 5
    @bandaMedia[server]=banda
    if banda != 0
      Log.escreve("Server #{server}: predição de banda = #{banda}")
    else
      Log.escreve("Server #{server}: 0 clientes")
    end
  end

  def self.reactive(server, dados)
    nums = Array.new
    linhas = dados.split(/\n/)
    linhas.each do |line|
      nums << line.split(',')[2].to_f
    end    
    banda = (nums[0] + nums[1] + nums[2] + nums[3] + nums[4]) / 5
    @bandaMedia[server]=banda
    if banda != 0 
      Log.escreve("Server #{server}: banda = #{banda}")
    else
      Log.escreve("Server #{server}: 0 clientes")
    end
  end

  def self.orchestrate()
    cont,soma = qtdServerAtivos
    media = soma/cont
    if media > 80000.0 and cont < 5
      scaleup()
    else
      limiar = 80000.0 * (cont - 1)
      if soma < limiar and cont > 1
        scaledown()
      end 
    end 
    @bandaMedia.each do |server, banda|
      if @listaDeMaquinas[server] != nil
        if banda > 85000.0 and (cont - qtdPausados) > 1 and @paused[server] != true
           pause(server)
        end
        if @paused[server] == true and banda < 70000.0
           unpause(server)
        end
      end
    end
  end

  def self.scaleup()
    @semaphore.synchronize {
      tempo = Time.now - @cooldown
      if tempo > 35        
        Log.escreve("Scaleup: adicionar servidor")
	puts "add server"
        ligar = nil
        @listaDeMaquinas.each do |ip, c|
          if c == nil
            ligar = ip
          end
        end
	puts "ligar o servidor #{ligar}"
        enable(ligar)
        @cooldown = Time.now
      else
        Log.escreve("Scaleup: cooldown not reached")
      end
    }
  end

  def self.scaledown()
    @semaphore.synchronize {
      qtd = qtdServerAtivos[0]   
      if qtd < 2
        Log.escreve("Scaledown: menos de 2 servidores (nada a fazer)")
      else
        tempo = Time.now - @cooldown
        if tempo > 35
          Log.escreve("Scaledown: remover servidor")
	  menor = 1000000.0
          ip = nil
          @bandaMedia.each do |server, banda|
            if @listaDeMaquinas[server] != nil
              if banda < menor
                ip = server
                menor = banda
              end
            end
          end
          disable(ip)
          @cooldown = Time.now
        else
          Log.escreve("Scaledown: cooldown not reached")
        end
      end
    }
  end

  #Inicia serviço
  Log.escreve("Iniciando o coletor...")
  puts "Iniciando coletor..."
  DRb.start_service
  enableinicial("<IP1>")
  sleep(5)
  enableinicial("<IP2>")
  sleep(5)
  disable("<IP2>")
  sleep(5)

#Habilita todas as máquinas (criando o objeto distribuído)
# @listaDeMaquinas.each do |ip, c|
#   #listaDeMaquinas[ip] = DRbObject.new nil, "druby://#{ip}:9000"
#   enable(ip)
# end
  i = 0
  while true
    collectTime = Time.now
    @listaDeMaquinas.each do |ip, c|
      if c != nil
	predict(ip, @listaDeMaquinas[ip].coletaServidor)
#	reactive(ip, @listaDeMaquinas[ip].coletaServidor)
      end
    end
    orchestrate
    #collect every 10 secs
    recollectTime = collectTime + 10
    if recollectTime > Time.now
    	sleep(recollectTime - Time.now)
    end
  end
end
