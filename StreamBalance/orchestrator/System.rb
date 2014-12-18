require 'drb'

module UFC
  class Coletor
    include DRbUndumped
    def coletaServidor  
	dadosServidor = `tail -n 5 /home/ubuntu/log.txt`
    end

    def coletaSNMP  
        dadosSNMP = `tail -n 5 logsnmp.txt`
    end

  end

  class Log
    def self.escreve(msg)
      log_file = File.open('execLog.txt', File::WRONLY | File::APPEND)
      logger = Logger.new(log_file)
      logger.level = Logger::INFO
      logger.info(msg)
      logger.close
    end
  end
end
