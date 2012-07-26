
# Runs brainfuck in a thread that is watched for performance hints
# also runs bf from an instruction point of view.
require 'stringio'
class OptimisingBrainfuckInterpreter
  
  MAX_CELL_VAL = 2**8


  def initialize(instructions, stats, tape_size, eof_behaviour, attempt_o1, simtime)
    @i                  = instructions
    @stats              = stats
    @tape_size          = tape_size
    @eof_behaviour      = eof_behaviour
    @attempt_o1         = attempt_o1
    @simtime            = simtime
    reset
  end 
 

  # Runs a deterministic routine with no input.
  # Captures the output 
  def sim_full_program_no_input
    @output = ""
    # new thread
    halted = false
    @time = Time.now
    t = Thread.new(){ 
      run 
      halted = true
    }
  
    # Wait
    100.times{|n|
      sleep(@simtime/100.0)
      $l.info "Simulating (~#{100-n}% remaining, #{@ic} instructions)..."
      break if halted
    }
    t.kill if not halted  

    # nicely kill thread, note if it finished.
    #puts "OUTPUT: '#{@output}'"
    @stats[:halting] = halted 
    @stats[:simtime] = @time-Time.now
    @stats[:output]  = @output if @attempt_o1
    return @stats
  end

  def sim_full_program(input)
    @input = input
    sim_full_program_no_input
  end

private

  # ------------------------ Interpreter control 
  def reset
    @input              = StringIO.new()
    build_jump_table
    create_tape
    @dp = 0
    @ip = 0
    @ic = 0
  end

  # Run unrestricted
  def run 
    while(@i[@ip]) do
      step
      @ip += 1
    end
  end

  # Interpret a single instruction
  def step
    @ic += 1  # increase instruction count
    i = @i[@ip]
    case i.type
        when Instruction::IDP then idp i, i.payload[:repeat]
        when Instruction::DDP then ddp i, i.payload[:repeat] 
        when Instruction::IDV then idv i, i.payload[:repeat] 
        when Instruction::DDV then ddv i, i.payload[:repeat] 
        when Instruction::OC  then oc  i, i.payload[:repeat] 
        when Instruction::IC  then ic  i, i.payload[:repeat] 
        when Instruction::LS  then ls  i, i.payload[:jump] 
        when Instruction::LE  then le  i, i.payload[:jump]
        when Instruction::ZDV then zdv i
        when Instruction::IPP then ipp i, i.payload[:print], i.payload[:shift]
      end

    # 0 if nil, else increase by one.
    i.payload[:sim_exec_count] = i.payload[:sim_exec_count] ? i.payload[:sim_exec_count] + 1 : 0 
  end

  # ------------------------ Interpreter logic
  def idp(i, n)
    @dp = @dp + n
    @dp = @tape.length-1 if @dp > @tape.length-1 # TODO: configurable limit limits
  end

  def ddp(i, n)
    @dp = @dp - n
    @dp = 0 if @dp < 0 # TODO: configurable limit limits
  end

  def idv(i, n)
    @tape[@dp] = adjust_val(@tape[@dp], n, MAX_CELL_VAL)
  end

  def ddv(i, n)
    @tape[@dp] = adjust_val(@tape[@dp], -1*n, MAX_CELL_VAL)
  end

  def input(i, n)
    n.times{|x|
      cin = @input.getc
      if @input.eof?
        case @eof_behaviour
          when -1 then @tape[@dp] = 255
          when  0 then @tape[@dp] = 0
        end
      else
        @tape[@dp] = cin
      end
    }
  end

  def oc(i, n)
    n.times{|x|
      @output << @tape[@dp].chr
    }
  end

  def ipp(i, print, shift)
    puts @tape[@dp..@dp+print].map{|x| x.chr}.join
    idp i shift # TODO: FIXME, this should have its own routine, rather than reusing one that may annotate.
  end 

  def zdv i 
    @tape[@dp] = 0
  end

  def ls(i, jump)
    @ip = token_to_instruction_id(jump) if @tape[@dp] == 0
  end

  def le(i, jump)
    @ip = token_to_instruction_id(jump) if @tape[@dp] != 0
  end

  # --------------------- Helpers  
  # low and high mod, limits at 0 .. lim
  def adjust_val(v, adjust, lim)
    v += adjust
    return v % lim 
  end

  # -------------------- Init
  # Build a table to convert from token id to instruction id and back
  def build_jump_table
    @jumptable = {}
    @i.each_index{|i|
      @jumptable[@i[i].payload[:token_id]] = i
    }
  end

  # Init the tape as 0s.
  def create_tape
    @tape = []
    @tape_size.times{|x| @tape[x] = 0 }
  end

  def token_to_instruction_id(token_id)
    return @jumptable[token_id]
  end

  def token_to_instruction(token_id)
    return @i[token_to_instruction_id(token_id)]
  end

  def instruction_to_token_id(instruction_id)
    return @i[instruction_id].payload[:token_id]
  end
end
