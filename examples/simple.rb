require 'rubygems'
require 'net/http/celluloid_io'
require 'uri'

class HttpClient
  include Celluloid::IO

  def get(uri)
    Net::HTTP::CelluloidIO.get(uri)
  end
end

class Requester
  include Celluloid

  def initialize
    @http_client = HttpClient.new
  end

  def requests
    u = URI.parse('http://www.google.com/index')
    10.times {
      futures = []
      30.times {
        futures << @http_client.future.get(u)
      }
      futures.each { |f|
        f.value
      }
    }
  end
end

Requester.new.requests 
Celluloid.shutdown
