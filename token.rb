
# A token
class Token
  attr_accessor :payload
  attr_reader :type, :char, :position

  def initialize(type, char, position, payload=nil)
    @type = type
    @char = char
    @position = position
    @payload = payload
  end

  def to_s
    return "<Token: position=#{@position}: type=#{@type}, char='#{@char}'>"
  end
end


