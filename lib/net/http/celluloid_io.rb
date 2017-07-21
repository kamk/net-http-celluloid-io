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
          begin
            Celluloid.timeout(sec, &blk)
          rescue Celluloid::TaskTimeout => e
            raise err_class.new(e)
          end
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
      Timeout.timeout(@read_timeout, Net::ReadTimeout) do
        @rbuf << @io.readpartial(BUFSIZE)
      end
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

    D "opening connection to #{conn_address}:#{conn_port}..."
    s = Timeout.timeout(@open_timeout, Net::OpenTimeout) {
      begin
        ::Celluloid::IO::TCPSocket.open(conn_address, conn_port, @local_host, @local_port)
      rescue => e
        raise e, "Failed to open TCP connection to " +
          "#{conn_address}:#{conn_port} (#{e.message})"
      end
    }
    s.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
    D "opened"
    if use_ssl?
      ssl_parameters = Hash.new
      iv_list = instance_variables
      SSL_IVNAMES.each_with_index do |ivname, i|
        if iv_list.include?(ivname) and
          value = instance_variable_get(ivname)
          ssl_parameters[SSL_ATTRIBUTES[i]] = value if value
        end
      end
      @ssl_context = OpenSSL::SSL::SSLContext.new
      @ssl_context.set_params(ssl_parameters)
      D "starting SSL for #{conn_address}:#{conn_port}..."
      s = ::Celluloid::IO::SSLSocket.new(s, @ssl_context)
      s.sync_close = true
      D "SSL established"
    end
    @socket = BufferedIO.new(s)
    @socket.read_timeout = @read_timeout
    @socket.continue_timeout = @continue_timeout
    @socket.debug_output = @debug_output
    if use_ssl?
      begin
        if proxy?
          buf = "CONNECT #{@address}:#{@port} HTTP/#{HTTPVersion}\r\n"
          buf << "Host: #{@address}:#{@port}\r\n"
          if proxy_user
            credential = ["#{proxy_user}:#{proxy_pass}"].pack('m')
            credential.delete!("\r\n")
            buf << "Proxy-Authorization: Basic #{credential}\r\n"
          end
          buf << "\r\n"
          @socket.write(buf)
          HTTPResponse.read_new(@socket).value
        end
        # Server Name Indication (SNI) RFC 3546
        s.hostname = @address if s.respond_to? :hostname=
        if @ssl_session and
           Process.clock_gettime(Process::CLOCK_REALTIME) < @ssl_session.time.to_f + @ssl_session.timeout
          s.session = @ssl_session if @ssl_session
        end
        if timeout = @open_timeout
          while true
            raise Net::OpenTimeout if timeout <= 0
            start = Process.clock_gettime Process::CLOCK_MONOTONIC
            # to_io is required because SSLSocket doesn't have wait_readable yet
            case s.connect_nonblock(exception: false)
            when :wait_readable; s.to_io.wait_readable(timeout)
            when :wait_writable; s.to_io.wait_writable(timeout)
            else; break
            end
            timeout -= Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
          end
        else
          s.connect
        end
        if @ssl_context.verify_mode != OpenSSL::SSL::VERIFY_NONE
          s.post_connection_check(@address)
        end
        @ssl_session = s.session
      rescue => exception
        D "Conn close because of connect error #{exception}"
        @socket.close if @socket and not @socket.closed?
        raise exception
      end
    end
    on_connect
  end
end
