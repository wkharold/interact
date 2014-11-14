require "interact"
require "stringio"


def ask_faked(input, question, opts = {})
  before = $stdout

  $stdout = StringIO.new("", "w")

  opts[:input] = StringIO.new(input, "r")

  yield AskResult.new(
    $interaction.ask(question, opts),
    $stdout.string
  )
ensure
  $stdout = before
end

class AskResult
  attr_reader :answer, :output

  def initialize(answer, output)
    @answer = answer
    @output = output
  end
end

class Interaction
  include Interactive
end

describe "asking" do
  before(:each) do
    $interaction = Interaction.new
  end

  describe "questions" do
    it "returns the answer string" do
      ask_faked("foo\n", "Foo?") do |x|
        x.answer.should == "foo"
        x.output.should == "Foo?: foo\n"
      end
    end

    it "skips blank lines until they enter something" do
      ask_faked("\n\nfoo\n", "Foo?") do |x|
        x.answer.should == "foo"
        x.output.should == "Foo?: \nFoo?: \nFoo?: foo\n"
      end
    end

    it "accepts blank lines if a default is provided; returns default" do
      ask_faked("\n\nfoo\n", "Foo?", :default => "bar") do |x|
        x.answer.should == "bar"
        x.output.should == "Foo? [bar]: \n"
      end
    end

    it "allows censoring output" do
      ask_faked("fizzbuzz\n", "Foo?", :echo => "*") do |x|
        x.answer.should == "fizzbuzz"
        x.output.should == "Foo?: ********\n"
      end
    end

    it "guesses the return type based on the default value" do
      ask_faked("y\n", "Foo?", :default => true) do |x|
        x.answer.should == true
        x.output.should == "Foo? [Yn]: y\n"
      end

      ask_faked("\n", "Foo?", :default => true) do |x|
        x.answer.should == true
        x.output.should == "Foo? [Yn]: \n"
      end

      ask_faked("n\n", "Foo?", :default => true) do |x|
        x.answer.should == false
        x.output.should == "Foo? [Yn]: n\n"
      end

      ask_faked("\n", "Foo?", :default => false) do |x|
        x.answer.should == false
        x.output.should == "Foo? [yN]: \n"
      end

      ask_faked("y\n", "Foo?", :default => false) do |x|
        x.answer.should == true
        x.output.should == "Foo? [yN]: y\n"
      end

      ask_faked("n\n", "Foo?", :default => false) do |x|
        x.answer.should == false
        x.output.should == "Foo? [yN]: n\n"
      end

      ask_faked("10\n", "Foo?", :default => 5) do |x|
        x.answer.should == 10
        x.output.should == "Foo? [5]: 10\n"
      end

      ask_faked("\n", "Foo?", :default => 5) do |x|
        x.answer.should == 5
        x.output.should == "Foo? [5]: \n"
      end
    end
  end

  describe "multiple choice" do
    it "can provide a set of choices to the user" do
      ask_faked("A\n", "Favorite letter?", :choices => "A".."C") do |x|
        x.answer.should == "A"
        x.output.should == "Favorite letter? (A, B, C): A\n"
      end
    end

    it "repeats the question if blank line received with no default" do
      ask_faked("\nA\n", "Favorite letter?", :choices => "A".."C") do |x|
        x.answer.should == "A"
        x.output.should == "Favorite letter? (A, B, C): \nFavorite letter? (A, B, C): A\n"
      end
    end

    it "can provide a set of choices to the user, with a default" do
      ask_faked("A\n", "Favorite letter?",
                :choices => "A".."C", :default => "C") do |x|
        x.answer.should == "A"
        x.output.should == "Favorite letter? (A, B, C) [C]: A\n"
      end
    end

    it "accepts blank lines if a default is provided; returns default" do
      ask_faked("\nA\n", "Favorite letter?",
                :choices => "A".."C", :default => "C") do |x|
        x.answer.should == "C"
        x.output.should == "Favorite letter? (A, B, C) [C]: \n"
      end
    end

    it "performs basic autocompletion" do
      ask_faked("c\n", "Foo?", :choices => %w{aa ba ca}) do |x|
        x.answer.should == "ca"
        x.output.should == "Foo? (aa, ba, ca): c\n"
      end

      ask_faked("cb\n", "Foo?", :choices => %w{aa ba caa cba}) do |x|
        x.answer.should == "cba"
        x.output.should == "Foo? (aa, ba, caa, cba): cb\n"
      end
    end

    it "complains if there is any ambiguity and repeats the question" do
      ask_faked("c\nca\n", "Foo?", :choices => %w{aa ba caa cba}) do |x|
        x.answer.should == "caa"
        x.output.should == "Foo? (aa, ba, caa, cba): c\nPlease disambiguate: caa or cba?\nFoo? (aa, ba, caa, cba): ca\n"
      end
    end

    it "can provide a listing view, and allow selecting by number" do
      ask_faked("B\n", "Foo?",
                :choices => "A".."C", :indexed => true) do |x|
        x.answer.should == "B"
        x.output.should == "1: A\n2: B\n3: C\nFoo?: B\n"
      end

      ask_faked("2\n", "Foo?",
                :choices => "A".."C", :indexed => true) do |x|
        x.answer.should == "B"
        x.output.should == "1: A\n2: B\n3: C\nFoo?: 2\n"
      end

      ask_faked("\n", "Foo?",
                :choices => "A".."C", :indexed => true, :default => "C") do |x|
        x.answer.should == "C"
        x.output.should == "1: A\n2: B\n3: C\nFoo? [C]: \n"
      end

      ask_faked("\nC\n", "Foo?",
                :choices => "A".."C", :indexed => true) do |x|
        x.answer.should == "C"
        x.output.should == "1: A\n2: B\n3: C\nFoo?: \nFoo?: C\n"
      end

      ask_faked("1,3-5,7\n2\n", "Foo?",
                :choices => "A".."G", :indexed => true) do |x|
        x.answer.should == "B"
        x.output.should == "1: A\n2: B\n3: C\n4: D\n5: E\n6: F\n7: G\nFoo?: 1,3-5,7\nUnknown answer, please try again!\nFoo?: 2\n"
      end
    end

    it "allows a user to select a range of items from a listing view" do
      ask_faked("1-3\n", "Foo?",
                :choices => "A".."C", :indexed => true, :allow_multi => true) do |x|
        x.answer.should == [1,2,3]
        x.output.should == "1: A\n2: B\n3: C\nFoo?: 1-3\n"
      end

      ask_faked("1,3\n", "Foo?",
                :choices => "A".."C", :indexed => true, :allow_multi => true) do |x|
        x.answer.should == [1,3]
        x.output.should == "1: A\n2: B\n3: C\nFoo?: 1,3\n"
      end

      ask_faked("3\n", "Foo?",
                :choices => "A".."C", :indexed => true, :allow_multi => true) do |x|
        x.answer.should == "C"
        x.output.should == "1: A\n2: B\n3: C\nFoo?: 3\n"
      end

      ask_faked("1,3,4-6\n", "Foo?",
                :choices => "A".."G", :indexed => true, :allow_multi => true) do |x|
        x.answer.should == [1,3,4,5,6]
        x.output.should == "1: A\n2: B\n3: C\n4: D\n5: E\n6: F\n7: G\nFoo?: 1,3,4-6\n"
      end

      ask_faked("1,3-5,7\n", "Foo?",
                :choices => "A".."G", :indexed => true, :allow_multi => true) do |x|
        x.answer.should == [1,3,4,5,7]
        x.output.should == "1: A\n2: B\n3: C\n4: D\n5: E\n6: F\n7: G\nFoo?: 1,3-5,7\n"
      end

      ask_faked("1-3,2-5,7\n", "Foo?",
                :choices => "A".."G", :indexed => true, :allow_multi => true) do |x|
        x.answer.should == [1,2,3,4,5,7]
        x.output.should == "1: A\n2: B\n3: C\n4: D\n5: E\n6: F\n7: G\nFoo?: 1-3,2-5,7\n"
      end
    end

    it "handles invalid range selections" do
      ask_faked("2,4\n2,3\n", "Foo?",
                :choices => "A".."C", :indexed => true, :allow_multi => true) do |x|
        x.answer.should == [2,3]
        x.output.should == "1: A\n2: B\n3: C\nFoo?: 2,4\nInvalid selection: 2,4\nFoo?: 2,3\n"
      end

      ask_faked("3-9\n2-4\n", "Foo?",
                :choices => "A".."G", :indexed => true, :allow_multi => true) do |x|
        x.answer.should == [2,3,4]
        x.output.should == "1: A\n2: B\n3: C\n4: D\n5: E\n6: F\n7: G\nFoo?: 3-9\nInvalid selection: 3-9\nFoo?: 2-4\n"
      end

      ask_faked("B,C""\n2\n", "Foo?",
                :choices => "A".."C", :indexed => true, :allow_multi => true) do |x|
        x.answer.should == "B"
        x.output.should == "1: A\n2: B\n3: C\nFoo?: B,C\nInvalid choice B,C please use the index numbers\nFoo?: 2\n"
      end
    end

    it "infers :indexed if :allow_multi is specified" do
      ask_faked("1,3-5,7\n", "Foo?",
                :choices => "A".."G", :allow_multi => true) do |x|
        x.answer.should == [1,3,4,5,7]
        x.output.should == "1: A\n2: B\n3: C\n4: D\n5: E\n6: F\n7: G\nFoo?: 1,3-5,7\n"
      end
    end
  end
end


