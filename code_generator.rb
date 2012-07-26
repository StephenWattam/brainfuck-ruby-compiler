

class CodeGenerator
  def initialize(tape_size, optimise, no_bounds_checking, debug_codegen, eof_behaviour)
    @no_bounds_checking = no_bounds_checking
    @debug_codegen = debug_codegen
    @eof_behaviour = eof_behaviour
    @tape_size = tape_size
    @optimise = optimise
  end
end


class BrainFuckCodeGenerator < CodeGenerator

  # STUB
  def generate_code(instructions, stats)
    @i, @stats = instructions, stats
  end

end

class StaticASMBrainFuckCodeGenerator < BrainFuckCodeGenerator
  TEMPLATE = %{# Compiled by SW's brainfuck compiler
# on %s
  
.text					
  .global _start	    # ELF Entry point (conventional, use ld -e to set)

_start:
    movl $%s,    %%edx       # Load n into edx
    movl $string,  %%ecx       # Load the address to print into ecx
    movl $1,    %%ebx       # file handle (stdout)
    movl $4,    %%eax       # syscall number (sys_write)
    int $0x80              # call the OS

_exit:                # Exit
  movl	$0, %%ebx		  # first argument: exit code
  movl	$1, %%eax		  # system call number (sys_exit)
  int	$0x80		        #  call kernel  

# ---------- [ Data Section ] ---------------
.data
string:
    .ascii "%s" 

} # TODO: escape the ASCII value ? 
  
  def initialize
  end

  def generate_code(string)
    return TEMPLATE % [Time.now.strftime("%c"), string.length, string]
  end
end

class ASMBrainFuckCodeGenerator < BrainFuckCodeGenerator
  CELL_VALUE = 2**8
  WORD_SIZE = 4

  HEADER = %{# Compiled by SW's Brainfuck Compiler
# on %s
  }
  MACROS = %{
.bss
# ------------------------------------------------------------------
# Read a single character from stdin, no EOF handling
# ------------------------------------------------------------------
  .macro stdin_read 
    movl $1, %edx         # Load n into edx
    movl %edi,%ecx          # Load the address to read into
    movl $0, %ebx	           # file handle (stdin)
    movl $3, %eax	           # Syscall number (sys_read)
    int $0x80                # call the OS
  .endm 

# ------------------------------------------------------------------
# Read a single character from stdin, EOF == 0
# ------------------------------------------------------------------
  .macro stdin_read_zero_eof jump
    stdin_read
    cmp $0, %eax          # Test for EOF
    jnz \\jump            # Skip over the EOF handler if not EOF
    movb $0, (%edi)
\\jump:
  .endm 

# ------------------------------------------------------------------
# Read a single character from stdin, EOF == -1 
# ------------------------------------------------------------------
  .macro stdin_read_neg_eof jump
    stdin_read
    cmp $0, %eax      # Test for EOF
    jnz \\jump        # skip over the EOF handler if not EOF
    movb $-1, (%edi)
\\jump:
  .endm 


# ------------------------------------------------------------------
# Output n character from the current data pointer to stdout
# ------------------------------------------------------------------
  .macro stdout_nchar n 
    movl $\\n,    %edx       # Load n into edx
    movl %edi,  %ecx       # Load the address to print into ecx
    movl $1,    %ebx       # file handle (stdout)
    movl $4,    %eax       # syscall number (sys_write)
    int $0x80              # call the OS
  .endm

# ------------------------------------------------------------------
# Output one character from the current data pointer to stdout
# ------------------------------------------------------------------
  .macro stdout_onechar 
    stdout_nchar 4
  .endm

# ------------------------------------------------------------------
# Start a loop 
# ------------------------------------------------------------------
  .macro loop_start label jump
    cmp  $0,     (%edi)           # Does the value at the data pointer == 0
    jz	\\jump                    # if so, jump to the jump address
\\label:                          # This instruction's label (jumped to during loop)
  .endm
# ------------------------------------------------------------------
# End a loop 
# ------------------------------------------------------------------
  .macro loop_end label jump
    cmp	$0, (%edi)           # Does the value at the data pointer == 0
    jnz	\\jump               # if so, jump to the jump address
\\label:                     # This instruction's label (jumped to during loop)
  .endm

# ------------------------------------------------------------------
# Increment Data Pointer (unsafe, no checks)
# ------------------------------------------------------------------
  .macro idp n
    addl $\\n, %edi         # Increment the data pointer without checks
  .endm

# ------------------------------------------------------------------
# Decrement Data Pointer (unsafe, no checks)
# ------------------------------------------------------------------
  .macro ddp n
    subl $\\n, %edi      
  .endm

# ------------------------------------------------------------------
# Increment Data Value  (byte)
# ------------------------------------------------------------------
  .macro idv n
    addb    $\\n, (%edi)   
  .endm


# ------------------------------------------------------------------
# Decrement Data Value  (byte)
# ------------------------------------------------------------------
  .macro ddv n
    subb    $\\n, (%edi)   
  .endm

# ------------------------------------------------------------------
# Zero Data Value  (word)
# ------------------------------------------------------------------
  .macro zdv
    movw $0, (%edi)     
  .endm

  }


  OPTIM_MACROS = %{
# ------------------------------------------------------------------
# Output n characters (buffered).
# (Only used if optimisations are turned on)
# ------------------------------------------------------------------
  .macro stdout_buffered_nchars n label
    # First, copy n chars to the buffer
    movl $\\n,  %ecx       # Put n in loop counter
    movl $buf,  %esi       # Move buffer address into ESI
\\label:
    movl (%edi),%eax       # Move EDI to ESI
    movl %eax,  (%esi)   
    incl %esi              # Increment ESI
    loop \\label

    # Then output n chars from the buffer
    movl $\\n, %edx
    movl $buf, %ecx
    movl $1, %ebx
    movl $4, %eax
    int $0x80
  .endm

}
  TEXT_HEADER = %{
.text					
  .global _start	    # ELF Entry point (conventional, use ld -e to set)

_start:
}
  EXIT = %{

_exit:                # Exit
  movl	$0, %ebx		  # first argument: exit code
  movl	$1, %eax		  # system call number (sys_exit)
  int	$0x80		        #  call kernel  
}
  TAPE = %{

# ---------- [ Data Section ] ---------------
.data
tape:
    .fill %s, 1, 0  # 30,000 cells at 1 word and set to 0
tape_end:
    .tapelen = . - tape # Length of tape, may be handy if I ever change it :-)

}


  def generate_code(instructions, stats)
    @i = instructions
    @stats = stats
    @s = ""
    produce_header
    produce_code
    produce_footer
    produce_data_tape
    return @s
  end

private
  def produce_header
    @s += HEADER % Time.now.strftime("%c")
    @s += MACROS
    @s += OPTIM_MACROS if @optimise
    @s += TEXT_HEADER 
  end

  def produce_data_tape
    @s += TAPE % @tape_size.to_s
    @s += %{
buf:
    .fill #{@stats[:longest_output_run]}, 1, 0     # 30k output buffer for faster output
    .buflen = . - buf  # length of output buffer
    } if @optimise and @stats[:longest_output_run] > 1
  end 

  def produce_code
    # Keep track of which instructions jump to which labels
    @jump_table = {}

    @s += zero_registers

    @i.each_index{|n|
      # Load the instruction at n, n is used as an ID
      i = @i[n]

      @s += debug_info(i, n, @i.length) if @debug_codegen

      @s += case i.type
              when Instruction::IDP then idp i, i.payload[:repeat]
              when Instruction::DDP then ddp i, i.payload[:repeat] 
              when Instruction::IDV then idv i, i.payload[:repeat] 
              when Instruction::DDV then ddv i, i.payload[:repeat] 
              when Instruction::OC  then oc  i, i.payload[:repeat] 
              when Instruction::IC  then ic  i, i.payload[:repeat] 
              when Instruction::LS  then ls  i, n, i.payload[:jump] 
              when Instruction::LE  then le  i, n, i.payload[:jump]
              when Instruction::ZDV then zdv i
              when Instruction::IPP then ipp i, i.payload[:print], i.payload[:shift]
            end 
    }

  end

  def debug_info(i, n, nlen)
    %{# Instruction #{n+1}/#{nlen} (type: #{i.type}, payload: #{i.payload}, token: #{i.token})
}    
  end

  def jump_label(j, postfix="loop")
    return "t#{j}_#{postfix}"
  end

  def produce_footer
    @s += EXIT
  end 

# ===================[ Instructions ]======================

  def zero_registers
    %{  # Startup, set registers and such.
  movl $tape, %edi         # Move the address of the tape into edi
}
  end

  # Print in-place.
  # This is produced by the optimiser where it sees .>.>.>.>.> and so on
  def ipp(i, p, s)  # print and shift
    %{  stdout_nchar #{p*WORD_SIZE}
  idp #{s*WORD_SIZE}
} 
  end

  # Zero the Data Value
  # This is produced by the optimiser where it sees [-]
  def zdv(i)
    # Set the value of the current cell to 0
    %{  zdv
}
  end
  
  # Increment the data pointer
  def idp(i, n)
    # Avoid unnecessarily large numbers
    # This means we only need to do a subtraction to handle bounds, so it's fast
    n = n % @tape_size
    return "" if n == 0

    # Increment by n, word aligned
    s = %{  idp #{n*WORD_SIZE}
}

    # FIXME: BOUNDS CHECKINGi (WRAP)
#    s += %{
#  cmpl	$tape_end, %edi   # Compare pointer to the end of the tape marker
#  jb	#{jump_label(i.payload[:token_id], 'bounds')}                   # if unsigned less than, jump over
#  subl	$#{@tape_size*4}, %edi        # else subtract and carry on (BUG WARNING if n > TAPE_SIZE)
##{jump_label(i.payload[:token_id], 'bounds')}:
#    } if not @no_bounds_checking
  
#    # BOUNDS CHECKING (exit)
#    s += %{
#  cmpl	$tape_end, (%edi)   # Compare pointer to the end of the tape marker
#  ja	_exit                  # if unsigned more than, jump out
#    } 
#
    # TODO: select type of bounds checking

    return s
  end

  # Decrement the data pointer
  def ddp(i, n)
    # Avoid unnecessarily large numbers
    # This means we only need to do a subtraction to handle bounds, so it's fast
    n = n% @tape_size
    return "" if n == 0

    # Decrement by n, word aligned
    s = %{  ddp #{n*WORD_SIZE}
}


#    # FIXME: BOUNDS CHECKING
#    s += %{
#  cmpl	$tape, %edi                                                    # Compare pointer to the end of the tape marker
#  jg	#{jump_label(i.payload[:token_id], 'bounds')}                   # if signed greater than 0, jump over else correct
#  addl	$#{@tape_size*4}, %edi                                        # else subtract and carry on (BUG WARNING if n > TAPE_SIZE)
##{jump_label(i.payload[:token_id], 'bounds')}:
#    } if not @no_bounds_checking
#

    return s
  end

  # Increment the data value
  def idv(i, n)
    # Add n to the value pointed at by the data pointer.
    # Mod with the cell value to prevent unnecessary wraparound.
    %{  idv #{n%CELL_VALUE}
}
  end

  # Decrement the data value
  def ddv(i, n)
    # Sub n from the value pointed at by the data pointer
    # Mod with the cell value to prevent unnecessary wraparound.
    %{  ddv #{n%CELL_VALUE}
}
  end

  # Output n characters
  def oc(i, n)
    if(@optimise and n > 1) then
      # Output using a buffer
      %{  stdout_buffered_nchars #{n} #{jump_label(i.payload[:token_id], 'output_loop')}
}
    else
      # Output in place for single chars or if optimisation is off 
      %{  stdout_onechar
} * n
    end
  end

  # Input n Characters
  def ic(i, n)
    # FIXME: this looping is very ugly.
    s = ""
    n.times{|j|
      case @eof_behaviour
        when "0" then s += %{  stdin_read_zero_eof #{jump_label(i.payload[:token_id], "eofinput_#{j}")}
} 
        when "-1" then s += %{  stdin_read_neg_eof #{jump_label(i.payload[:token_id], "eofinput_#{j}")}
} 
        else s += %{  stdin_read
}
      end
    }
    return s
  end

  # Start a loop
  def ls(i, n, j)
    # Call the loop start macro with the skip label and the current instruction label
  %{  loop_start #{jump_label(i.payload[:token_id])} #{jump_label(j)}
}
  end

  # End a loop
  def le(i, n, j)
    # Call the loop end macro with the skip label and the current instruction label
    %{  loop_end #{jump_label(i.payload[:token_id])} #{jump_label(j)}
} 
  end
end
