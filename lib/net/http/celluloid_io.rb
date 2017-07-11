# encoding: utf-8
require 'celluloid/io'
require 'net/http'
require 'timeout'

class Net::HTTP::CelluloidIO < Net::HTTP
  # 
  module Timeout
    def self.timeout(sec=nil, err_class=nil, &blk)
      if Celluloid.actor?
        if sec
          Celluloid.timeout(sec, &blk)
        else
          blk.call
        end
      else
        ::Timeout.timeout(sec, err_class, &blk)
      end
    end

    def timeout(*args, &blk)
      Timeout.timeout(*args, &blk)
    end
  end

  class BufferedIO < Net::BufferedIO
    include Timeout

    def rbuf_fill
      #TODO: trap @read_timeout.
      @rbuf << @io.readpartial(BUFSIZE)
    end
  end

  include Timeout

  private
  
  def connect
    if Celluloid.actor? && Celluloid.current_actor.kind_of?(Celluloid::IO)
      connect_celluloid
    else
      D "using original Net::HTTP#connect"
      super
    end
  end
  
  def connect_celluloid
    if proxy? then
      conn_address = proxy_address
      conn_port    = proxy_port
    else
      conn_address = address
      conn_port    = port
    end
    
    D "opening connection to #{conn_address}..."
    s = timeout(@open_timeout) { ::Celluloid::IO::TCPSocket.new(conn_address, conn_port) }
    D "opened"
    if use_ssl?
      ssl_parameters = Hash.new
      iv_list = instance_variables
      SSL_ATTRIBUTES.each do |name|
        ivname = "@#{name}".intern
        if iv_list.include?(ivname) and
            value = instance_variable_get(ivname)
          ssl_parameters[name] = value
        end
      end
      @ssl_context = OpenSSL::SSL::SSLContext.new
      @ssl_context.set_params(ssl_parameters)
      s = ::Celluloid::IO::SSLSocket.new(s.to_io, @ssl_context)
      s.to_io.sync_close = true
    end
    @socket = BufferedIO.new(s)
    @socket.read_timeout = @read_timeout
    @socket.continue_timeout = @continue_timeout
    @socket.debug_output = @debug_output
    if use_ssl?
      begin
        if proxy?
          @socket.writeline sprintf('CONNECT %s:%s HTTP/%s',
                                    @address, @port, HTTPVersion)
          @socket.writeline "Host: #{@address}:#{@port}"
          if proxy_user
            credential = ["#{proxy_user}:#{proxy_pass}"].pack('m')
            credential.delete!("\r\n")
            @socket.writeline "Proxy-Authorization: Basic #{credential}"
          end
          @socket.writeline ''
          HTTPResponse.read_new(@socket).value
        end
        # Server Name Indication (SNI) RFC 3546
        s.to_io.hostname = @address if s.to_io.respond_to?(:hostname=)
        timeout(@open_timeout) { s.connect }
        if @ssl_context.verify_mode != OpenSSL::SSL::VERIFY_NONE
          s.to_io.post_connection_check(@address)
        end
      rescue => exception
        D "Conn close because of connect error #{exception}"
        @socket.close if @socket and not @socket.closed?
        raise exception
      end
    end
    on_connect
  end
end

