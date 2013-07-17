# -*- coding: utf-8 -*-
require 'seeing_is_believing'
require 'stringio'

describe SeeingIsBelieving do
  def invoke(input, options={})
    described_class.new(input, options).call
  end

  def values_for(input)
    invoke(input).to_a
  end

  let(:proving_grounds_dir) { File.expand_path '../../proving_grounds', __FILE__ }

  it 'takes a string or and returns a result of the line numbers (counting from 1) and each inspected result from that line' do
    input  = "1+1\n'2'+'2'"
    invoke(input)[1].should == ["2"]
    invoke(input)[2].should == ['"22"']
  end

  it 'remembers context of previous lines' do
    values_for("a=12\na*2").should == [['12'], ['24']]
  end

  it 'can be invoked multiple times, returning the same result' do
    believer = described_class.new("$xyz||=1\n$xyz+=1")
    believer.call.to_a.should == [['1'], ['2']]
    believer.call.to_a.should == [['1'], ['2']]
  end

  it 'is evaluated at the toplevel' do
    values_for('self').should == [['main']]
  end

  it 'records the value immediately, so that it is correct even if the result is mutated' do
    values_for("a = 'a'\na << 'b'").should == [['"a"'], ['"ab"']]
  end

  it 'records each value when a line is evaluated multiple times' do
    values_for("(1..2).each do |i|\ni\nend").should == [[], ['1', '2'], ['1..2']]
  end

  it 'evalutes to an empty array for lines that it cannot understand' do
    vs = values_for('if true &&
                          if true &&
                                    true
                            1
                          end
                  2
                end').should == [[], [], ['true'], ['1'], ['1'], ['2'], ['2']]

    values_for("[3].map do |n|\n n*2\n end").should == [[], ['6'], ['[6]']]

    values_for("[1].map do |n1|
                  [2].map do |n2|
                    n1 + n2
                  end
                end").should == [[], [], ['3'], ['[3]'], ['[[3]]']]

    values_for("[1].map do |n1|
                  [2].map do |n2| n1 + n2
                  end
                end").should == [[], [], ['[3]'], ['[[3]]']]

    values_for("[1].map do |n1|
                  [2].map do |n2|
                    n1 + n2 end
                end").should == [[], [], ['[3]'], ['[[3]]']]

    values_for("[1].map do |n1|
                  [2].map do |n2|
                    n1 + n2 end end").should == [[], [], ['[[3]]']]

    values_for("[1].map do |n1|
                  [2].map do |n2| n1 + n2 end end").should == [[], ['[[3]]']]

    values_for("[1].map do |n1| [2].map do |n2| n1 + n2 end end").should == [['[[3]]']]

    values_for("[1].map do |n1|
                  [2].map do |n2|
                    n1 + n2
                end end").should == [[], [], ['3'], ['[[3]]']]

    values_for("[1].map do |n1| [2].map do |n2|
                  n1 + n2
                end end").should == [[], ['3'], ['[[3]]']]

    values_for("[1].map do |n1| [2].map do |n2|
                  n1 + n2 end end").should == [[], ['[[3]]']]

    values_for("[1].map do |n1| [2].map do |n2|
                  n1 + n2 end
                end").should == [[], [], ['[[3]]']]

    values_for("1 +
                    2").should == [[], ['3']]

    values_for("'\n1\n'").should == [[], [], ['"\n1\n"']]

    # fails b/c parens should go around line 1, not around entire expression -.^
    # values_for("<<HEREDOC\n1\nHEREDOC").should == [[], [], ['"\n1\n"']]
    # values_for("<<-HEREDOC\n1\nHEREDOC").should == [[], [], ['"\n1\n"']]
  end

  it "does not record expressions that are here docs (only really b/c it's not smart enough)" do
    values_for("<<A\n1\nA").should be_all &:empty?
    values_for(" <<A\n1\nA").should be_all &:empty?
    values_for("<<-A\n1\n A").should be_all &:empty?
    values_for(" <<-A\n1\n A").should be_all &:empty?
    values_for("s=<<-A\n1\n A").should be_all &:empty?
    values_for("def meth\n<<-A\n1\nA\nend").should == [[], [], [], [], ['nil']]
  end

  it 'does not insert code into the middle of heredocs' do
    invoked = invoke(<<-HEREDOC.gsub(/^      /, ''))
      puts <<DOC1
      doc1
      DOC1
      puts <<-DOC2
      doc2
      DOC2
      puts <<-DOC3
      doc3
        DOC3
      puts <<DOC4, <<-DOC5
      doc4
      DOC4
      doc5
      DOC5
    HEREDOC

    invoked.stdout.should == "doc1\ndoc2\ndoc3\ndoc4\ndoc5\n"
  end

  it 'has no output for empty lines' do
    values_for('').should == [[]]
    values_for('  ').should == [[]]
    values_for("  \n").should == [[]]
    values_for("1\n\n2").should == [['1'],[],['2']]
  end

  it 'stops executing on errors and reports them' do
    invoke("'no exception'").should_not have_exception

    result = invoke("12\nraise Exception, 'omg!'\n12")
    result.should have_exception
    result.exception.message.should == 'omg!'

    result[1].should == ['12']

    result[2].should == []
    result[2].exception.should == result.exception

    result[3].should == []
    result.to_a.size.should == 3
  end

  it 'records the backtrace on the errors' do
    result = invoke("12\nraise Exception, 'omg!'\n12")
    result.exception.backtrace.should be_a_kind_of Array
  end

  it 'does not fuck up __LINE__ macro' do
    values_for('__LINE__
                __LINE__

                def meth
                  __LINE__
                end
                meth

                # comment
                __LINE__').should == [['1'], ['2'], [], [], ['5'], ['nil'], ['5'], [], [], ['10']]
  end

  it 'does not try to record a return statement when that will break it' do
    values_for("def meth \n return 1          \n end \n meth").should == [[], [], ['nil'], ['1']]
    values_for("def meth \n return 1 if true  \n end \n meth").should == [[], [], ['nil'], ['1']]
    values_for("def meth \n return 1 if false \n end \n meth").should == [[], [], ['nil'], ['nil']]
    values_for("-> {  \n return 1          \n }.call"        ).should == [[], [], ['1']]
    # this doesn't work because the return detecting code is a very conservative regexp
    # values_for("-> { return 1 }.call"        ).should == [['1']]
  end

  it 'does not try to record the keyword next' do
    values_for("(1..2).each do |i|\nnext if i == 1\ni\nend").should == [[], [], ['2'], ['1..2']]
  end

  it 'does not try to record the keyword redo' do
    values_for(<<-DOC).should == [[], ['0'], [], ['1', '2', '3', '4'], [], ['0...3'], ['nil'], ['0...3']]
      def meth
        n = 0
        for i in 0...3
          n += 1
          redo if n == 2
        end
      end
      meth
    DOC
  end

  it 'does not try to record the keyword retry' do
    values_for(<<-DOC).should == [[], [], [], ['nil']]
      def meth
      rescue
        retry
      end
    DOC
  end

  it 'does not try to record the keyword retry' do
    values_for(<<-DOC).should == [[], ['0'], [], ['nil']]
      (0..2).each do |n|
        n
        break
      end
    DOC
  end

  it 'does not affect its environment' do
    invoke 'def Object.abc() end'
    Object.should_not respond_to :abc
  end

  it 'captures the standard output and error' do
    result = invoke "2.times { puts 'a', 'b' }
                     STDOUT.puts 'c'
                     $stdout.puts 'd'
                     STDERR.puts '1', '2'
                     $stderr.puts '3'
                     $stdout = $stderr
                     puts '4'"
    result.stdout.should == "a\nb\n" "a\nb\n" "c\n" "d\n"
    result.stderr.should == "1\n2\n" "3\n" "4\n"
    result.should have_stdout
    result.should have_stderr

    result = invoke '1+1'
    result.should_not have_stdout
    result.should_not have_stderr
  end

  it 'defaults the filename to temp_dir/program.rb' do
    result = invoke('print File.expand_path __FILE__')
    File.basename(result.stdout).should == 'program.rb'
  end

  it 'can be told to run as a given file (in a given dir/with a given filename)' do
    filename = File.join proving_grounds_dir, 'mah_file.rb'
    FileUtils.rm_f filename
    result   = invoke 'print File.expand_path __FILE__', filename: filename
    result.stdout.should == filename
  end

  specify 'cwd of the file is the cwd of the evaluating program' do
    filename = File.join proving_grounds_dir, 'mah_file.rb'
    FileUtils.rm_f filename
    invoke('print File.expand_path(Dir.pwd)', filename: filename).stdout.should == Dir.pwd
  end

  it 'does not capture output from __END__ onward' do
    values_for("1+1\nDATA.read\n__END__\n....").should == [['2'], ['"...."']]
  end

  it 'raises a SyntaxError when the whole program is invalid' do
    expect { invoke '"' }.to raise_error SyntaxError
  end

  it 'can be given a stdin stream' do
    invoke('$stdin.read', stdin: StringIO.new("input"))[1].should == ['"input"']
  end

  it 'can be given a stdin string' do
    invoke('$stdin.read', stdin: "input")[1].should == ['"input"']
  end

  it 'defaults the stdin stream to an empty string' do
    invoke('$stdin.read')[1].should == ['""']
  end

  it 'can deal with methods that are invoked entirely on the next line' do
    values_for("a = 1\n.even?\na").should == [[], ['false'], ['false']]
    values_for("1\n.even?\n__END__").should == [[], ['false']]
  end

  it 'does not record leading comments' do
    values_for("# -*- coding: utf-8 -*-\n'ç'\n__LINE__").should == [[], ['"ç"'], ['3']]
    values_for("=begin\n1\n=end\n=begin\n=end\n__LINE__").should == [[], [], [],
                                                                     [], [],
                                                                     ['6']]
  end

  it 'times out if the timeout limit is exceeded' do
    expect { invoke "sleep 0.2", timeout: 0.1 }.to raise_error Timeout::Error
  end

  it 'records the exit status' do
    invoke('raise "omg"').exitstatus.should == 1
    invoke('exit 123').exitstatus.should == 123
    invoke('at_exit { exit 121 }').exitstatus.should == 121
  end

  it 'records lines that have comments on them' do
    values_for('1+1 # comment uno
                #comment dos
                3#comment tres').should == [['2'], [], ['3']]
  end

  it "doesn't fuck up when there are lines with magic comments in the middle of the app" do
    values_for('1+1
                # encoding: wtf').should == [['2'], []]
  end

  it "doesn't remove multiple leading comments" do
    values_for("#!/usr/bin/env ruby\n"\
               "# encoding: utf-8\n"\
               "'ç'").should == [[], [], ['"ç"']]
    values_for("#!/usr/bin/env ruby\n"\
               "1 # encoding: utf-8\n"\
               "2").should == [[], ['1'], ['2']]
  end

  it 'can record the middle of a chain of calls', not_implemented: true  do
    values_for("[*1..5]
                  .select(&:even?)
                  .map { |n| n * 3 }").should == [['[1, 2, 3, 4, 5]'],
                                                  ['[2, 4]'],
                                                  ['[6, 12]']]
    # values_for("[*1..5]
    #               .select(&:even)
    #               .map { |n| n * 2 }.
    #               map  { |n| n / 2 }\
    #               .map { |n| n * 3 }").should == [['[1, 2, 3, 4, 5]'],
    #                                               ['[2, 4]'],
    #                                               ['[4, 8]'],
    #                                               ['[2, 4]'],
    #                                               ['[6, 12]']]
    # values_for("1 +\n2").should == [['1'], ['3']]
    # values_for("1\\\n+ 2").should == [['1'], ['3']]
  end

end
