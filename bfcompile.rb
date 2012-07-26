#
#      Brainfuck compiler UI
#
###################################
#
#  Author: Stephen Wattam
# 
# TODO
# 
#  * Clean up the UI, adding options for common things
#  * Check tape wraparound edge cases
#  * Get more stuff configured such as EOF behaviour
#  * Add a debug operator
#  * Add input buffering (possibly)
#  * Add more optimisations once proven
#  * Find a decent, stable, benchmark.
#  * DOcs! (eof_behaviour = 0 for return 0, -1 for return -1, or anything else/unset for unchanged


# ========================== UI =========================
# Loads settings from a command line list into $s.
def parse_cmdargs(array)
  require 'shellwords'
  $s = {}
  
  # Defaults
  default_false = %w{}
  default_true  = %w{}

  # Defaults
  default_false.each{|x| $s[x.to_sym] = false }
  default_true. each{|x| $s[x.to_sym] = true  }

  # For each argument
  array.each{|arg|
    set   = arg.match(/^-?(?<key>[a-z0-9]+)([=:-](?<value>.+))?$/)
    if set then
      k = set[:key].to_sym

      # Handle default values
      v = true
      if set[:value] then
        words = Shellwords.shellsplit(set[:value])
        v = words[0] if words.length == 1
        v = words    if words.length > 1
      end
      
      # Set value
      $s[k] = v

      $l.debug("Set #{k} = #{$s[k]}")

    end
  }
  
  # Load useful forms of filenames, etc
  load_file_as_setting("i", $s[:i], "ifn", "r", $stdin)
  load_file_as_setting("o", $s[:o], "ofn", "w", $stdout)
  load_file_as_setting("e", $s[:e], "efn", "w", $stderr)
end

# Load a file into $s with default fallbacks.
def load_file_as_setting(key, fn, key2, mode, default=nil)
  # Do nothing if nothing to be done.
  return if fn == nil and default == nil

  # Default
  if fn == nil
    $s[key.to_sym] = default
    return
  end
  
  # Set, with filename stored
  $s[key.to_sym] = File.open(fn, mode)
  $s[key2.to_sym] = fn
end

# Print to stdout
def sputs(str)
  $s[:o].puts str
end

# Print to stderr
def eputs(str)
  $s[:e].puts str
end

# get from stdin
def sgets(str)
  $s[:i].gets
end



# ========================== Run =========================
# ---------------- [ Step 0: Configuration ] -------------------------
# Load command line configs
# TODO: Load token sets and longer config items
#
# TODO: allow configuration of code generators and tokenisers
#
require 'logger'
$l = Logger.new($stdout)
$l.level = Logger::DEBUG


require './instruction.rb'
BRAINFUCK_TOKENS = {
  Instruction::IDP  => ">",
  Instruction::DDP  => "<",
  Instruction::IDV  => "+",
  Instruction::DDV  => "-",
  Instruction::OC   => ".",
  Instruction::IC   => ",",
  Instruction::LS   => "[",
  Instruction::LE   => "]"
}




# Load settings
parse_cmdargs(ARGV)
$s[:tapesize] = 30000 if not $s[:tapesize]

# Reload logger with new settings :-)
$l = Logger.new($s[:logfn]) if $s[:logfn]
$l.level = Logger::DEBUG # TODO


# ---------------- [ Step 1: Tokenisation ] -------------------------
# Load Tokens from the input source
# TODO: configurable token sets
#
# TODO: make passes to improve performance
# for now, load everything into one big list
# this may ultimately be necssary to perform some cool optimisations
#
require './token.rb'
require './tokeniser.rb'
tokeniser = Tokeniser.new(BRAINFUCK_TOKENS, $s[:i])


# ---------------- [ Step 1.5: Parsing ] -------------------------
# Check brackets line up
# Note down depth
# Convert tokens to instructions
#
#parser = Parser.new(tokeniser)
#instructions = parser.parse
# TODO: split the below stage into a parser when it's dealing with tokens, and an optimiser when it's dealing with instructions


# ---------------- [ Step 2: Optimisation ] -------------------------
# Fill in the payload of each instruction 
# Produce more complex instructions from arrays of simpler ones
# Perform simulations to identify heavily used code areas
# Optimise using local analysis
#
# TODO: split this into a parser when it's dealing with tokens, and an optimiser when it's dealing with instructions
require './optimiser.rb'
optimiser = BrainFuckOptimiser.new(tokeniser)
instructions, stats = optimiser.optimise
$l.info "Optimisation stats: #{stats}"


# TODO: move this into the optimiser
# Perform PGO on scopes and full program
if $s[:simtime].to_f > 0

  # Load the simulator
  require './simulator.rb'
  sim_timeout = $s[:simtime].to_f
  $l.info "Attempting simulation with timeout of ~#{sim_timeout}s."
  simulator = OptimisingBrainfuckInterpreter.new(instructions, stats, $s[:tapesize].to_i, $s[:eof].to_i, $s[:attemptstatic], sim_timeout)

  # Simulate
  if not stats[:deterministic] then
    if not $s[:siminput] then
      raise "Cannot simulate a program that requires input without an input file."
    end
    $l.warn "Behaviour after instruction #{stats[:first_input]} may rely on user input, will do the best I can."
    # TODO
    # Simulate first n and keep tape values
  else
    $l.info "Program has no input --- if it halts in time I can compile a very fast binary."
    stats = simulator.sim_full_program_no_input
  end
    
  # Simulation is complete. 
  $l.info "Simulation complete."
  if stats[:halting] and stats[:output] and $s[:attemptstatic] then
    $l.info "Program halted.  No need for static analysis, I have all I need..."
  else
    # local analysis
    $l.info "TODO: static analysis and PGO... STUB!!"
    # Use statistics from simulation to inform further optimisations
    # move this into the optimiser too, when done
    # TODO: perform proper local analysis
    # TODO: if $s[:profilestats] print output on most heavily used loops, etc 
  end
end




# ---------------- [ Step 3: Code Generation ] -------------------------
# Pass to a code generation library, probably run into GAS to begin with
#
require './code_generator.rb'
# Check for O(1) compatiblity
if $s[:attemptstatic] and stats[:halting] and stats[:output] then
  $l.info "Producing static (& speedy) output, woo!"
  # Fold everything into a single instruction
  instructions = [Instruction.new(Instruction::SOUT, nil, {:static_output => stats[:output], :token_id => 0, :instruction_id => 0, :depth => 0})]
  code_generator = StaticASMBrainFuckCodeGenerator.new()
  sputs(code_generator.generate_code(instructions[0].payload[:static_output]))
  $l.info "Done."
else
  # Generate normal code
  code_generator = ASMBrainFuckCodeGenerator.new($s[:tapesize].to_i, $s[:foptimise], $s[:noboundcheck], $s[:debugcodegen], $s[:eof])
  sputs(code_generator.generate_code(instructions, stats))
end


# ---------------------- [ Dot file Generation ] ---------------------
# Generate a dot file if desired
if $s[:dotfile] then
  $l.info "Producing instruction-flow dot file at #{$s[:dotfile]}..."
  require './dot_generator.rb'
  dot_generator = BrainFuckInstructionDotGenerator.new
  File.open($s[:dotfile], 'w').write(
    dot_generator.render(instructions)
  )
  $l.info "Done."
end



