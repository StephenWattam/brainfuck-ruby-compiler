class DotGenerator

  def initialize()
  end

#private
end


class BrainFuckInstructionDotGenerator < DotGenerator
  HEADER = "digraph main{\n"
  FOOTER = "}"

  def render(instructions)
    @i = instructions   

    @s = HEADER
    produce_symbols
    produce_loop_edges
    produce_normal_flow
    @s += FOOTER

    return @s
  end

private
  def instruction_to_string(i)
    label = case i.type
              when Instruction::LS  then "["
              when Instruction::LE  then "]"
              when Instruction::IDP then ">> #{i.payload[:repeat]}"
              when Instruction::DDP then "<< #{i.payload[:repeat]}"
              when Instruction::IDV then "+ #{i.payload[:repeat]}"
              when Instruction::DDV then "- #{i.payload[:repeat]}"
              when Instruction::OC  then "putc #{i.payload[:repeat]}"
              when Instruction::IC  then "getc #{i.payload[:repeat]}"
              #-- compound instructions 
              when Instruction::ZDV then "[-]"
              when Instruction::IPP then "print #{i.payload[:print]} >> #{i.payload[:shift]}"
              when Instruction::SOUT then "static output"
              else "? (#{i.type.to_s})"
            end

    #label += "d: #{i.payload[:depth]}"
    "i_#{i.payload[:token_id]}[label=\"#{label}\"]"
  end

  def draw_edge(from, to)
    return "i_#{from} -> i_#{to};"
  end

  def draw_subgraph_header(id, scope, depth)
    return "subgraph cluster_#{id} { \nlabel=\"scope: #{scope} (depth: #{depth})\"; \nnode [style=filled,color=white];"
  end

  def draw_subgraph_footer()
    return "}"
  end

  def produce_symbols
    @i.each{|i|
      @s += "#{instruction_to_string(i)}\n"
    }
  end

  def produce_normal_flow
    a = @i[0]
    (@i.length-1).times{|i|
      b = @i[i+1]
     
      #puts "#{b} depth: #{b.payload[:depth]}" 
      @s += "#{draw_subgraph_footer}\n" if(a.payload[:depth] > b.payload[:depth])
      @s += "#{draw_edge(a.payload[:token_id], b.payload[:token_id])}\n"
      @s += "#{draw_subgraph_header(b.payload[:token_id], b.payload[:scope], b.payload[:depth])}\n" if(a.payload[:depth] < b.payload[:depth])

      a = b
    }

    @s += "#{draw_subgraph_footer}\n" if a.payload[:depth] > 0
  end

  def produce_loop_edges
    @i.each{|i|
      @s += "#{draw_edge(i.payload[:token_id], i.payload[:jump])}\n" if i.type == Instruction::LE or i.type == Instruction::LS
    }
  end
end


#graph g{
#  subgraph clustermain{
#    color = lightgrey;quantum=5;main [shape=box]
#
#    subgraph clustersetXYZ{
#color=lightgrey;quantum=5;setXYZ [shape=box]
#
#setXYZ -- setX [dir=forward,taillabel=0,labelfontsize=10]
#
#setX -- setY [dir=forward,taillabel=1,labelfontsize=10]
#
#setY -- setZ [dir=forward,taillabel=2,labelfontsize=10]
#setResult
#
##setZ -- setResult [dir=forward,taillabel=3,labelfontsize=10]
#}
#
#main -- setXYZ [dir=forward,taillabel=0,labelfontsize=10]
#subgraph clusterCalc{
#color=lightgrey;quantum=5;Calc [shape=box]
#t1
#
#Calc -- t1 [dir=forward,taillabel=0,labelfontsize=10]
#t2
#
#t1 -- t2 [dir=forward,taillabel=1,labelfontsize=10]
#res
#
#t2 -- res [dir=forward,taillabel=2,labelfontsize=10]
#}
#
#setXYZ -- Calc [dir=forward,taillabel=1,labelfontsize=10]
#PrintResult
#
#Calc -- PrintResult [dir=forward,taillabel=2,labelfontsize=10]
#}
#z[color=blue,fontcolor=blue,fontsize=8]"t2" -- "z"[color=blue,weight=0.5]
#result[color=blue,fontcolor=blue,fontsize=8]"setResult" -- "result"[color=blue,weight=0.5]
#y[color=blue,fontcolor=blue,fontsize=8]"t1" -- "y"[color=blue,weight=0.5]
#x[color=blue,fontcolor=blue,fontsize=8]"t1" -- "x"[color=blue,weight=0.5]
#result[color=blue,fontcolor=blue,fontsize=8]"setXYZ" -- "result"[color=blue,weight=0.5]
#y[color=blue,fontcolor=blue,fontsize=8]"main" -- "y"[color=blue,weight=0.5]
#x[color=blue,fontcolor=blue,fontsize=8]"main" -- "x"[color=blue,weight=0.5]
#result[color=blue,fontcolor=blue,fontsize=8]"main" -- "result"[color=blue,weight=0.5]
#z[color=blue,fontcolor=blue,fontsize=8]"main" -- "z"[color=blue,weight=0.5]
#y[color=blue,fontcolor=blue,fontsize=8]"Calc" -- "y"[color=blue,weight=0.5]
#x[color=blue,fontcolor=blue,fontsize=8]"Calc" -- "x"[color=blue,weight=0.5]
#result[color=blue,fontcolor=blue,fontsize=8]"Calc" -- "result"[color=blue,weight=0.5]
#z[color=blue,fontcolor=blue,fontsize=8]"Calc" -- "z"[color=blue,weight=0.5]
#result[color=blue,fontcolor=blue,fontsize=8]"res" -- "result"[color=blue,weight=0.5]
#result[color=blue,fontcolor=blue,fontsize=8]"PrintResult" -- "result"[color=blue,weight=0.5]
#}
##
