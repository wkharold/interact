# Copyright (c) 2012 Alex Suraci
module Interactive
  EVENTS = {
    "\b" => :backspace,
    "\t" => :tab,
    "\x01" => :home,
    "\x03" => :interrupt,
    "\x04" => :eof,
    "\x05" => :end,
    "\x17" => :kill_word,
    "\x7f" => :backspace,
    "\r" => :enter,
    "\n" => :enter
  }

  ESCAPES = {
    "[A" => :up, "H" => :up,
    "[B" => :down, "P" => :down,
    "[C" => :right, "M" => :right,
    "[D" => :left, "K" => :left,
    "[3~" => :delete, "S" => :delete,
    "[H" => :home, "G" => :home,
    "[F" => :end, "O" => :end,
    "[Z" => :shift_tab
  }

  # Wrap around the input options, the current answer, and the current
  # position.
  #
  # Passed to handlers, which are expected to mutate +answer+ and +position+
  # as they handle incoming events.
  class InputState
    attr_accessor :options, :answer, :position

    def initialize(options = {}, answer = "", position = 0)
      @options = options
      @answer = answer
      @position = position
      @done = false
    end

    # Call to signal to the input reader that it can stop.
    def done!
      @done = true
    end

    # Is the input finished/complete?
    def done?
      @done
    end

    def censor(what)
      if with = @options[:echo]
        with * what.size
      else
        what
      end
    end

    def display(what)
      print(censor(what))
      @position += what.size
    end

    def back(x)
      return if x == 0

      print("\b" * (x * char_size))

      @position -= x
    end

    def clear(x)
      return if x == 0

      print(" " * (x * char_size))

      @position += x

      back(x)
    end

    def goto(pos)
      return if pos == position

      if pos > position
        display(answer[position .. pos])
      else
        print("\b" * (position - pos) * char_size)
      end

      @position = pos
    end

    private

    def char_size
      @options[:echo] ? @options[:echo].size : 1
    end
  end

  # Read a single character.
  #
  # [options] An optional hash containing the following options.
  #
  # input::
  #   The input source (defaults to <code>$stdin</code>).
  def read_char(options = {})
    input = options[:input] || $stdin

    with_char_io(input) do
      get_character(input)
    end
  end

  # Read a single event.
  #
  # [options] An optional hash containing the following options.
  #
  # input::
  #   The input source (defaults to <code>$stdin</code>).
  def read_event(options = {})
    input = options[:input] || $stdin

    with_char_io(input) do
      get_event(input)
    end
  end

  # Read a line of input.
  #
  # [options] An optional hash containing the following options.
  #
  # input::
  #   The input source (defaults to <code>$stdin</code>).
  #
  # echo::
  #   A string to echo when showing the input; used for things like hiding
  #   password input.
  def read_line(options = {})
    input = options[:input] || $stdin

    state = input_state(options)
    with_char_io(input) do
      until state.done?
        handler(get_event(input), state)
      end
    end

    state.answer
  end

  # Ask a question and get an answer.
  #
  # See Interact#read_line for the other possible values in +options+.
  #
  # [question] The prompt, without ": " at the end.
  #
  # [options] An optional hash containing the following options.
  #
  # default::
  #   The default value, also used to attempt type conversion of the answer
  #   (e.g. numeric/boolean).
  #
  # choices::
  #   An array (or +Enumerable+) of strings to choose from.
  #
  # indexed::
  #   Use alternative choice listing, and allow choosing by number. Good
  #   for when there are many choices or choices with long names.
  def ask(question, options = {})
    choices = options[:choices] && options[:choices].to_a

    list_choices(choices, options) if choices

    while true
      prompt(question, options)
      ok, res = answered(read_line(options), options)
      return res if ok
    end
  end

  private

  def clear_input(state)
    state.goto(0)
    state.clear(state.answer.size)
    state.answer = ""
  end

  def set_input(state, input)
    clear_input(state)
    state.display(input)
    state.answer = input
  end

  def redraw_input(state)
    pos = state.position
    state.goto(0)
    state.display(state.answer)
    state.goto(pos)
  end

  def input_state(options)
    InputState.new(options)
  end

  def get_event(input)
    escaped = false
    escape_seq = ""

    while true
      c = get_character(input)

      if not c
        return :eof
      elsif c == "\e" || c == "\xE0"
        escaped = true
      elsif escaped
        escape_seq << c

        if cmd = ESCAPES[escape_seq]
          return cmd
        elsif ESCAPES.select { |k, v|
                k.start_with? escape_seq
              }.empty?
          escaped, escape_seq = false, ""
        end
      elsif EVENTS.key? c
        return EVENTS[c]
      elsif c < " "
        # ignore
      else
        return [:key, c]
      end
    end
  end

  def answered(ans, options)
    print "\n"

    if ans.empty?
      if options.key?(:default)
        [true, options[:default]]
      end
    elsif choices = options[:choices]
      matches = []

      choices.each do |x|
        completion = choice_completion(x, options)

        if completion == ans
          return [true, x]
        elsif completion.start_with? ans
          matches << x
        end
      end

      if choices and ans =~ /^\s*\d+\s*$/ and \
          ans.to_i - 1 >= 0 and res = choices.to_a[ans.to_i - 1]
        [true, res]
      elsif matches.size == 1
        [true, matches.first]
      elsif matches.size > 1
        matches_list = matches.collect { |m|
          show_choice(m, options)
        }.join " or "

        puts "Please disambiguate: #{matches_list}?"

        [false, nil]
      elsif options[:allow_multi]
        expand_multi_choice(options[:choices].to_a.size, ans)
      elsif options[:allow_other]
        [true, ans]
      else
        puts "Unknown answer, please try again!"
        [false, nil]
      end
    else
      [true, match_type(ans, options[:default])]
    end
  end

  def list_choices(choices, options = {})
    options[:indexed] = true if options[:allow_multi]

    return unless options[:indexed]

    choices.each_with_index do |o, i|
      puts "#{i + 1}: #{show_choice(o, options)}"
    end
  end

  def expand_multi_choice(max_choice, choice)
    selection = []
    choices = choice.split(',')
    choices.each do |c|
      case
        when is_number?(c) then
          selection.push(c.to_i)
        when is_range?(c) then
          expand_range(c).each {|rv| selection.push(rv) unless selection.include? rv}
        else
          puts "Invalid choice #{choice} please use the index numbers"
          return [false, nil]
      end
    end
    if valid_range?(max_choice, selection)
      [true, selection]
    else
      puts "Invalid selection: #{choice}"
      [false, nil]
    end
  end

  def expand_range(range)
    m = /([[:digit:]])+-([[:digit:]])+/.match(range)
    (m[1].to_i..m[2].to_i).to_a
  end

  def is_number? s
    true if Integer(s) rescue false
  end

  def is_range?(s)
    m = /([[:digit:]])+-([[:digit:]])+/.match(s)
    (m == nil) ? false : m[1].to_i < m[2].to_i
  end

  def valid_range?(max, rng)
    rng.select {|rv| rv <= 0 || rv > max}.length == 0
  end

  def show_choice(choice, options = {})
    display = options[:display] || proc(&:to_s)
    display.call(choice)
  end

  def choice_completion(choice, options = {})
    complete = options[:complete] || options[:display] || proc(&:to_s)
    complete.call(choice)
  end

  def common_prefix(*strs)
    return strs.first.dup if strs.size == 1

    longest = strs.sort_by(&:size).last
    longest.size.times do |i|
      sub = longest[0..(-1 - i)]
      if strs.all? { |s| s.start_with?(sub) }
        return sub
      end
    end

    ""
  end

  def handler(which, state)
    ans = state.answer
    pos = state.position

    case which
    when :up
      # nothing

    when :down
      # nothing

    when :tab
      matches =
        if choices = state.options[:choices]
          choices.collect { |c|
            choice_completion(c, state.options)
          }.select { |c|
            c.start_with? ans
          }
        else
          matching_paths(ans)
        end

      if matches.empty?
        print("\a") # bell
      else
        old = ans
        ans = state.answer = common_prefix(*matches)
        state.display(ans[pos .. -1])
        print("\a") if ans == old
      end

    when :right
      unless pos == ans.size
        state.display(ans[pos .. pos])
      end

    when :left
      unless pos == 0
        state.back(1)
      end

    when :delete
      unless pos == ans.size
        ans.slice!(pos, 1)
        rest = ans[pos .. -1]
        state.display(rest)
        state.clear(1)
        state.back(rest.size)
      end

    when :home
      state.goto(0)

    when :end
      state.goto(ans.size)

    when :backspace
      if pos > 0
        rest = ans[pos .. -1]

        ans.slice!(pos - 1, 1)

        state.back(1)
        state.display(rest)
        state.clear(1)
        state.back(rest.size)
      end

    when :interrupt
      raise Interrupt.new

    when :eof
      state.done! if ans.empty?

    when :kill_word
      if pos > 0
        start = /[[:alnum:]]*\s*[^[:alnum:]]?$/ =~ ans[0 .. (pos - 1)]

        if pos < ans.size
          to_end = ans.size - pos
          rest = ans[pos .. -1]
          state.clear(to_end)
        end

        length = pos - start

        ans.slice!(start, length)
        state.back(length)
        state.clear(length)

        if to_end
          state.display(rest)
          state.back(to_end)
        end
      end

    when :enter
      state.done!

    when Array
      case which[0]
      when :key
        c = which[1]
        rest = ans[pos .. -1]

        ans.insert(pos, c)

        state.display(c + rest)
        state.back(rest.size)
      end

    else
      return false
    end

    true
  end

  def matching_paths(input)
    home = File.expand_path("~")

    Dir.glob(input.sub("~", home) + "*").collect do |p|
      p.sub(home, "~")
    end
  end

  def prompt(question, options = {})
    print question

    if (choices = options[:choices]) && !options[:indexed]
      print " (#{choices.collect(&:to_s).join ", "})"
    end

    case options[:default]
    when true
      print " [Yn]"
    when false
      print " [yN]"
    when nil
    else
      print " [#{options[:default]}]"
    end

    print ": "
  end

  def match_type(str, x)
    case x
    when Integer
      str.to_i
    when true, false
      str.upcase.start_with? "Y"
    else
      str
    end
  end

  def with_char_io(input)
    before = set_input_state(input)
    yield
  ensure
    restore_input_state(input, before)
  end

  def chr(x)
    case x
    when nil
      nil
    when String
      x
    else
      x.chr
    end
  end

  private :chr

  # Definitions for reading character-by-character with no echoing.
  begin
    require "Win32API"

    def set_input_state(input)
      nil
    end

    def restore_input_state(input, state)
      nil
    end

    def get_character(input)
      if input == STDIN
        begin
          chr(Win32API.new("msvcrt", "_getch", [], "L").call)
        rescue
          chr(Win32API.new("crtdll", "_getch", [], "L").call)
        end
      else
        chr(input.getc)
      end
    end
  rescue LoadError
    begin
      require "termios"

      def set_input_state(input)
        return nil unless input.tty?
        before = Termios.getattr(input)

        new = before.dup
        new.c_lflag &= ~(Termios::ECHO | Termios::ICANON)
        new.c_cc[Termios::VMIN] = 1

        Termios.setattr(input, Termios::TCSANOW, new)

        before
      end

      def restore_input_state(input, before)
        if before
          Termios.setattr(input, Termios::TCSANOW, before)
        end
      end

      def get_character(input)
        chr(input.getc)
      end
    rescue LoadError
      begin
        require "ffi-ncurses"

        def set_input_state(input)
          return nil unless input.tty?

          FFI::NCurses.initscr
          FFI::NCurses.cbreak

          true
        end

        def restore_input_state(input, before)
          if before
            FFI::NCurses.endwin
          end
        end

        def get_character(input)
          chr(input.getc)
        end
      rescue LoadError
        def set_input_state(input)
          return nil unless input.tty?

          before = `stty -g`

          Kernel.system("stty -echo -icanon isig")

          before
        end

        def restore_input_state(input, before)
          Kernel.system("stty #{before}") if before
        end

        def get_character(input)
          chr(input.getc)
        end
      end
    end
  end
end
