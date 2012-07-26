# Internal representation of brainfuck
#
# Represented as "normal" brainfuck, plus some operations that represent
# common patterns.
class Instruction 
  # Normal Brainfuck Instructions
  IDP = :idp # Increment Data Pointer
  DDP = :ddp # Decrement Data Pointer
  IDV = :idv # Increment Data Value
  DDV = :ddv # Decrement Data Value
  OC  = :oc  # Output Character
  IC  = :ic  # Input Character
  LS  = :ls  # Loop start
  LE  = :le  # Loop end

  # Hueristic and super-instruction optimisations
  ZDV = :zdv # [-] Zero Data Value
  IPP = :ipp # .>.>.>. in place print of tape, payload[:print_length] == how much to run for
  # setoffset >+< >-< <-> <+> (<<+>>, <<->>, >>-<<, >>+<<)
  SOUT = :sout # Static output, string to be found in payload[:static_output]

  attr_accessor :payload
  attr_reader :type, :token

  def initialize(type, token=nil, payload={})
    @token = token
    @type = type
    @payload = payload
  end

  def to_s
    return "<Instruction: type=#{@type}: token=#{@token}>"
  end
end
