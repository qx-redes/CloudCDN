#!/usr/bin/ruby

def nextTime(rateParameter)
    return - Math.log(1.0 - rand) / rateParameter
end

def defRate(clientes)
# quantidade de clientes a cada 5 minutos
     return 1.0 / (300.0 / clientes)
#    return 1.0 / (3600.0 / clientes)
end

def run(nroclientes)
  rate = defRate(nroclientes)
  videos = ["MovieMedium.mov", "MovieHi.mov", "MovieLow.mov"]
  puts "Iniciando #{nroclientes} clientes: #{Time.now}"
  port = 10000
  i = 0
  while port < (10000 + (10*nroclientes))
    i = i + 1
    sleep(nextTime(rate))
    vid = videos[rand(2)]
    cmd = "rtspclient.o rtsp://<IP>:554/stressVideos/#{vid} #{port} #{3+rand(3)} < /dev/null > /dev/null 2>&1 &"
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
    cmd = "rtspclient.o rtsp://<IP>:554/stressVideos/#{vid} #{port} #{3+rand(3)} < /dev/null > /dev/null 2>&1 &"
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

#run(100)
#run(150)
#run(200)
#run(400)
#run(100)
#run(200)
#run(600)
#run(1000)
#run(800)
#run(500)
#run(800)
#run(1000)
nowRunAll(50)
