#!/usr/bin/ruby

filename = 'dist.txt'
@distribution = Array.new
@prox = 0

File.open(filename, 'r').each_line do |line|
  @distribution << line.to_i
end

def nextTime(rateParameter)
    return - Math.log(1.0 - rand) / rateParameter
end

def getNext
  @prox = @prox + 1
  return @distribution[@prox - 1]
end

def defRate(clientes)
# quantidade de clientes a cada 5 minutos
     return 1.0 / (300.0 / clientes)
#    return 1.0 / (3600.0 / clientes)
end

def run(nroclientes)
  rate = defRate(nroclientes)
  videos = ["4.39-240p.mp4", "4.39-360p.mp4", "4.39-480p.mp4", "4.39-720p.mp4", "4.39-1080p.mp4"]
  puts "Iniciando #{nroclientes} clientes: #{Time.now}"
  port = 10000
  i = 0
  while port < (10000 + (10*nroclientes))
    i = i + 1
    sleep(nextTime(rate))
    #vid = videos[rand(2)]
    vid = videos[getNext()]
    cmd = "./exec-parser.rb rtspclient-withsound.o rtsp://<IP>:554/youtube/#{vid} #{port} #{1+rand(8)}"
    Thread.new do
        job = fork do
                exec cmd
        end
        Process.detach(job)
    end
    puts "Cliente #{i} iniciado... "
    port = port + 10
  end
  puts "#{nroclientes} iniciados: #{Time.now}"
end

def nowRunAll(nroclientes)
  videos = ["MovieMedium.mov", "MovieHi.mov", "MovieLow.mov"]
  puts "Iniciando #{nroclientes} clientes: #{Time.now}"
  port = 10000
  i = 0
  while port < (10000 + (10*nroclientes))
    sleep(0.05)
    vid = videos[rand(2)]
    cmd = "./exec-parser.rb rtspclient-withsound.o rtsp://<IP>:554/stressVideos/#{vid} #{port} #{3+rand(3)}"
    Thread.new do
	job1 = fork do
  		exec cmd
	end
	Process.detach(job1)
    end
    port = port + 10
  end
  puts "#{nroclientes} iniciados: #{Time.now}"
end

run(50)
run(100)
run(120)
run(200)
run(100)
run(200)
run(250)
run(350)
run(400)
run(500)
run(550)
run(400)
run(300)
run(250)
run(200)
run(300)
run(350)
run(450)
run(600)
run(300)
run(500)
run(300)
run(250)
run(150)
run(50)
