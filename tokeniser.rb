

module Math
  def self.min(a, b)
    return (a<b) ? a : b
  end
end


# A general purpose minimal-source-readahead tokeniser with some basic error checking
# Designed for brainfuck, it offers token readahead too...
require './token.rb'
class Tokeniser
  # Starts a new tokeniser with a given set of tokens
  # tokens are specified in a {:type => "value", :type => ["val1", "val2"]} format.
  # lists and items can be mixed.
  def initialize(t, input=$stdin)
    self.tokens = t
    self.input = input
    @tokenbuf = []
  end

  # Set the input source
  def input=(i)
    @input = i
    @buffer = ""
    @pos = 1
    @line = 1
  end

  # until a token is read, keep reading chars from input
  def get_token
    @tokenbuf << read_token if @tokenbuf.length == 0
    return @tokenbuf.shift
  end
  alias :next_token :get_token

  # Shows the nth next token, but does not consume it
  # warning, this is like habving a 1-indexed array (1st next token == tokenbuffer[0])
  def peek_token(n=1)
    n.times{|x| @tokenbuf << read_token if @tokenbuf.length == 0 }
    return @tokenbuf[n-1]
  end

  # Adds a token to the beginning of the array
  def unget_token(t)
    @tokenbuf.unshift(t)
  end

  # Has the tokeniser hit the EOF?
  def eof?
    @input.eof?
  end


  #Load tokens, transforming {:k => v} into {:k => [:v]} and leaving {:k => [:v1, :v2]}
  def tokens=(t)
    @tokens = {}
    t.each{|k,v|
      @tokens[k] = (v.class.to_s == "Array") ? v : [v]
    }

    # Check for ambiguity and compute longest for later
    raise "Tokens are ambiguous" if test_token_ambiguity
    @longest_token = find_longest_token

    return @tokens
  end


private
  def read_token
    c = ""#next character
    while(not (@buffer.length == 0 and eof?)) do
      @buffer = (@buffer[1..-1]) ? (@buffer[1..-1]) : "" # this ugly ternary catches the starting edge case

      # Match against buffer
      while(@buffer.length <= @longest_token and not eof?) do
        t = match_tokens # matches tokens and shortens the buffer
    
        # Read a new char and add it to the buffer, unless it's EOF
        c = getc
        @buffer += c if not eof?

        #leave the buffer with something in
        return t if t
      end
    end
    return nil
  end

  # tries to match the buffer precisely.
  def match_tokens
    (1..@buffer.length).each{|n|
      @tokens.each{|k,vs|
        vs.each{|v| # Each value of each token
          # If match
          #puts "#{@buffer[0..n]} -- #{v}"
          if @buffer[0..n] == v then
            t = Token.new(k, v, "#{@line-@buffer.count("\n")}.#{@pos-@buffer.length}", nil) # Construct token, compensate for readahead
            @buffer = @buffer[n-1..-1]  # Cut from left of buffer
            return t # return token
          end
        }
      }
    }
    return nil
  end

  # private, gets a character and updates line, position counts.
  def getc
    # Read c
    c = @input.getc

    # Maintain counters
    if c == "\n"
      @line += 1
      @pos = 1
    else
     @pos += 1
    end

    # Return char
    return c
  end

  # Ronseal. Returns length
  def find_longest_token
    longest = 0
    @tokens.each{|k,vs| vs.each{|v| longest = v.length if v.length > longest }}
    return longest
  end
  

  # Ensure tokens do not overlap, so can be unambiguously read 
  def test_token_ambiguity
    @tokens.keys.each{|i|
      @tokens.keys.each{|j|
        if(i!=j) then
          ti = @tokens[i]
          tj = @tokens[j]

          # Loop over all possible values for each given token
          ti.each{|tiv|
            tj.each{|tjv|
              return true if tiv[0..Math::min(tiv.length, tjv.length)-1] == tjv[0..Math::min(tiv.length, tjv.length)-1]
            }
          }
        end
      }
    }
    return false
  end

end


# Test pack
if __FILE__ == $0
#  puts "test of token checks"
#  puts "test 1"
#  Tokeniser.new({:l => "l", :t => "tee"})
#  puts "test 2"
#  Tokeniser.new({:l => "l", :t => ["bonbiu", "t"], :x => ["test", "TEST"]})
  #x =  Tokeniser.new({
      #:class => "Class",
      #:def => "def",
      #:equality => "==",
      #:log => "$l",
      #:return => "return",
      #:if => "if"
      
      #}, File.open("bfcompile.rb", 'r'))
  

  # brainfuck
  x =  Tokeniser.new({
      :incdp => ">",
      :decdp => "<",
      :incdv => "+",
      :decdv => "-",
      :outc => ".",
      :inc => ",",
      :sloop => "[",
      :eloop => "]"
      
      }, File.open("bench.b", 'r'))
  while(y = x.get_token) do
    puts "#{y.type.to_s} : #{y.char.to_s} @ #{y.position}"
  end
end
