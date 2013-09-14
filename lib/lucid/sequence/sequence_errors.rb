module Sequence
  
  class SequenceError < StandardError
  end
  
  class DuplicateSequenceError < SequenceError
    def initialize(phrase)
      super("A sequence with phrase '#{phrase}' already exists.")
    end
  end

  class UnknownSequenceError < SequenceError
    def initialize(phrase)
      super("Unknown sequence step with phrase: '#{phrase}'.")
    end
  end

  class EmptyParameterError < SequenceError
    def initialize(text)
      super("An empty or blank parameter occurred in '#{text}'.")
    end
  end
  
end