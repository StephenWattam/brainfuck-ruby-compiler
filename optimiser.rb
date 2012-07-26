
module Math
  def self.min(a, b)
    return a if b.nil?
    return b if a.nil?
    return (a<b) ? a : b
  end
end
#
# TODO
#
#  PGO: run and test for determinism and wraparound.
# 
#
class Optimiser 
  def initialize(token_source)
    @token_source = token_source
  end

  def optimise 
  end

end

require './instruction.rb'
class BrainFuckOptimiser < Optimiser 

  # Perform basic parsing and optimisations
  def optimise
    $l.info "Performing optimisation..."
    load_tokens
    annotate
    build_instructions
    #@i.each{|i| puts "#{i.token.payload[:token_id]}, #{i}, #{i.payload}"  }
    build_meta_instructions
    compute_instruction_id
    build_scope
   
    # Calculate these last 
    compute_optimisation_stats
    return @i, @stats
  end

  # Compute statistics on optimisations and potential
  def compute_optimisation_stats
    $l.info "Computing Optimisation flags and stats..."
    @stats = {}
    longest_output_run
    io_present
    position_of_first_closure
    compute_simulation_limit
  end
 
  # Run a simulator to count loops of the program, 
  # and the first n data values, etc
  def simulate
  end

  # Use data from the simulation to optimise
  def perform_pgo
  end

private

  # Compute the longest output run,
  # necessary for calculating the buffer size when optimising in/output
  def longest_output_run
    $l.debug "Calculating longest single output run..."
    lior = 0
    @i.each{|i|
      lior = i.payload[:repeat] if i.type == Instruction::OC and i.payload[:repeat] > lior
    }
    @stats[:longest_output_run] = lior
  end

  # How far is it safe to precompute?
  # ASSUMES HALTING!
  def compute_simulation_limit
    $l.debug "Computing limit on first-n instructions that can be simulated safely..."
    fi = @stats[:first_input]
    fc = @stats[:first_closure]

    if fi.nil? then
      sl = fc.nil? ? @i.length : Math::min( fi, fc )
    else  
      sl = fi
    end
    
    @stats[:simulate_first_n] = sl
  end

  # Find the place where code starts to loop
  def position_of_first_closure
    $l.debug "Calculating position of first loop/closure..."
    @i.each_index{|i|
      if @i[i].payload[:depth] > 0 then
        @stats[:first_closure] = i-1
        return
      end
    }
    @stats[:first_closure] = nil
  end

  # See if the program is determinstic
  def io_present
    $l.debug "Counting first instance of IO instructions..."
    fi = nil
    fo = nil

    # Count io instructions
    c = -1 
    while(i = @i[c+=1] and (not fi or not fo)) do
      fo = i.payload[:instruction_id] if not fo and i.type == Instruction::OC
      fi = i.payload[:instruction_id] if not fi and i.type == Instruction::IC
    end

    @stats[:first_input]    = fi # instruction id
    @stats[:first_output]   = fo # instruction id
    @stats[:deterministic]  = fi == nil # determinstic if no input
  end

  def build_instructions
    $l.debug "Creating instructions from tokens..."
    @i = []

    # Convert RLE into run length deely
    @t.each{|t|
      # Every command should have a repeat count over 0, or not set at all
      @i << Instruction.new(t.type, t, t.payload) if (t.payload[:repeat] == nil or t.payload[:repeat] > 0)
    }
  end

  def compute_instruction_id
    $l.debug "Generating instruction IDs..."
    # Instruction ID to go with token id
    @i.each_index{|i|
      @i[i].payload[:instruction_id] = i
    }
  end

  # Provide logical optimisations based on instruction-space ops.
  def build_meta_instructions
    # (1)
    # Find and replace '[-]' combination with the zero instruction
    $l.debug "Identifying zero-setting pattern [-]..."
    while(i = @i.map{|x| x.type}.sub_index([Instruction::LS, Instruction::DDV, Instruction::LE])) do
      @i.replace_at!(i, 3, [Instruction.new(Instruction::ZDV, @i[i].token, 
            {:repeat => 1, :all_instructions => [@i[i].token, @i[i+1].token, @i[i+2].token], :depth => @i[i].payload[:depth]-1, :token_id => @i[i].token.payload[:token_id]})])
    end

    # (2)
    # Compute in-place-print sequence .>.>.>.>.>
    # Find patterns, and progressively replace them
    # Ruby doesn't like multiple assignment in conditionals, hence the duplication of the start, run assignment line
    $l.debug "Identifying in-place print candidate patterns..."
    pattern = [[Instruction::OC, 1], [Instruction::IDP, 1]] # only work where repeat => 1
    start, run = @i.map{|x| [x.type, x.payload[:repeat]]}.find_pattern_run( pattern  )
    while(start and run)
      prt = run # print this many chars
      sft = run # shift this many chars
      ist  = run * pattern.length # Replace this many instructions
    
      #puts "i.length: #{@i.length}, #{start+ist}"

      # Catch an edge case where the last print does not shift
      if @i.length > start+ist and @i[start+ist].type == Instruction::OC and @i[start+ist].payload[:repeat] == 1 then
        ist += 1
        prt += 1
      end

      # back up old instructions
      old_instructions = @i[start..start+ist-1]
      #puts old_instructions.join(" * \n")

      # Replace the entries in the array
      @i.replace_at!(start, ist, [Instruction.new(Instruction::IPP, @i[start].token, 
            {:print => prt, :shift => sft, :repeat => 1, :all_instructions => old_instructions, :depth => @i[start].token.payload[:depth], :token_id => @i[start].token.payload[:token_id]})])

      # Scan again
      start, run = @i.map{|x| [x.type, x.payload[:repeat]]}.find_pattern_run( pattern  )
    end
  end

  def build_scope
    $l.debug "Building scope identifiers..."
    a = @i[0]
    scope_count = 0
    scopes = [0] #stack

    @i[1..-1].each{|b|
      scopes.push(scope_count += 1) if a.type == Instruction::LS 
      a.payload[:scope] = scopes[-1]
      scopes.pop if a.type == Instruction::LE 
       
      a = b
    }
  end

  def load_tokens
    # Load all tokens
    @t = []
    while(y = @token_source.get_token) do
      y.payload = {}
      @t << y
    end
    $l.debug "Loaded #{@t.length} tokens."
  end

  # Annotate instructions
  def annotate
    # Annotate tokens!
    build_jump_references

    return @t
  end
  
  # Builds "loop" references both forward and back
  def build_jump_references
    $l.debug "Building jump references and depths"
    depth = 0
      
    @t.each_index{|i|
      t = @t[i]

      t.payload[:token_id] = i
      t.payload[:depth] = depth
      #puts "#{t}: #{depth} #{t.payload}"
  


      # Set token vals
      if(t.type == Instruction::LS) then
        depth += 1
        t.payload[:depth] += 1 #ensure loops are of equal depth
        t.payload[:jump] = scan(1, Instruction::LS, Instruction::LE, i)
      end

      if(t.type == Instruction::LE) then
        depth -= 1
        t.payload[:jump] = scan(-1, Instruction::LE, Instruction::LS, i)
      end

      # RLE repeatable chars for sum/loop logic
      if([Instruction::IDP, Instruction::DDP, Instruction::IDV, Instruction::DDV, Instruction::OC, Instruction::IC].include? t.type) then
        scan_rle(1, t.type, i)
      end
    }
    raise "Loop start/end does not match (loop depth at end: #{depth})." if depth != 0 

    return @t
  end

  # Scan forwards or backwards in an instruction list, keeping track of
  # start and end characters to find matching pairs
  # The alternative is recursive, and easier ;-)
  def scan(dir, s, e, ip)
    dep = 1
    ip += dir
    while(ip >= 0 and ip < (@t.length))
      dep += 1 if(@t[ip].type == s)
      dep -= 1 if(@t[ip].type == e)
      return ip if dep == 0
      ip += dir
    end
    
    return nil 
  end

  # Optimise commonly repeated operations
  def scan_rle(dir, symbol, ip)
    return 0 if @t[ip].payload[:repeat] # skip if prepopulated

    # compute run length
    c = 1
    while((ip+c) >= 0 and (ip+c) < (@t.length) and @t[ip+c].type == symbol) #lazy evaluation ftw.
      c += 1
    end

    # Write repeat values and prestuff the others counted
    @t[ip].payload[:repeat] = c
    (c-1).times{|n| @t[ip+1+n].payload[:repeat] = 0 } 

    # Return run length
    return c
  end

end


# ------------------- Support code for the optimiser --------------------
# A quick bit of test code
class Array 
  # Produces the first index where a given series of characters exists
  # or nil if it does not
  def sub_index(a, fn=nil)
    return nil if a.length == 0 or a.length > self.length
    fn = a.method(:==) if not fn # By default do a simple find

    (self.length - a.length + 1).times{|i|
      #puts "#{i}, #{self[i..i+a.length-1]} == #{a} : #{self[i..i+a.length] == a}"
      return i if a == self[i..i+a.length-1]
    }
    return nil
  end

  # Produces a list of matches of a in self.
  def sub_indices(a, fn=nil)
    return nil if a.length == 0 or a.length > self.length
    fn = a.method(:==) if not fn # By default do a simple find
    
    r = []
    (self.length - a.length + 1).times{|i|
      r << i if a == self[i..i+a.length-1] 
    }
    return r
  end

  # Replace self[i..i+len-1] with ar, regardless of ar's length
  def replace_at(i, len, ar)
    # Rotate until i is exposed
    #puts "self: #{self}, self.rotate(i): #{self.rotate(i)}"
    self.rotate(i+len)[0..-(len+1)].push(*ar).rotate(-1*(i+ar.length))
  end

  # Persistent form of replace_at
  def replace_at!(i, len, ar)
    self.replace(replace_at(i, len, ar))
  end

  # Finds the first location where a pattern repeats indefinitely
  def find_pattern_run(pattern)
    return nil if pattern.length == 0
    start = 0
    run = 0

    i = 0
    while(i < (self.length-pattern.length+1)) do
      if self[i..i+pattern.length-1] == pattern then
        start = i if start == 0
        run += 1
        i += pattern.length-1 # -1 to compensate for later addition
        #puts "*"
      else
        #puts "  r? #{run > 1}"
        return start, run if run > 1
        start = 0
        run = 0
      end
      #puts "P: #{ self[i..i+pattern.length-1]}, start: #{start}, run: #{run}"
      i+= 1
    end 
    return start, run if run > 1
    return nil
  end

end
  
#a = [1,2,2,3,1,2,1,2,1,2,1,2]
#a = ['+', '[', '-', ']', '+']
#puts "Sub index test ---> #{a.sub_indices([1,0,2])}"
#puts a.replace_at( 1, 3, ['z']).to_s
#puts "Patterns ----> #{a.find_pattern_run([1,2])}"



