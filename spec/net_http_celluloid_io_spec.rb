# encoding: utf-8
require 'spec_helper'
require 'uri'
require 'celluloid/rspec'

class TestClient
  include Celluloid::IO

  def get(uri)
    Net::HTTP::CelluloidIO.get(uri)
  end
end

describe 'Net::HTTP::CelluloidIO' do
  it 'gets from example.com' do
    TestClient.new.get(URI.parse('http://example.com/path'))
  end
end
