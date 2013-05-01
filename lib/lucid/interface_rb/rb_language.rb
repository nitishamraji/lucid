require 'lucid/core_ext/instance_exec'
require 'lucid/interface_rb/rb_lucid'
require 'lucid/interface_rb/rb_world'
require 'lucid/interface_rb/rb_step_definition'
require 'lucid/interface_rb/rb_hook'
require 'lucid/interface_rb/rb_transform'
require 'lucid/interface_rb/snippet'

begin
  require 'rspec/expectations'
rescue LoadError
  begin
    require 'spec/expectations'
    require 'spec/runner/differs/default'
    require 'ostruct'
  rescue LoadError
    require 'test/unit/assertions'
  end
end

module Lucid
  module InterfaceRb
    # Raised if a World block returns Nil.
    class NilWorld < StandardError
      def initialize
        super("World procs should never return nil")
      end
    end

    # Raised if there are 2 or more World blocks.
    class MultipleWorld < StandardError
      def initialize(first_proc, second_proc)
        message = "You can only pass a proc to #World once, but it's happening\n"
        message << "in 2 places:\n\n"
        message << first_proc.backtrace_line('World') << "\n"
        message << second_proc.backtrace_line('World') << "\n\n"
        message << "Use Ruby modules instead to extend your worlds. See the Lucid::InterfaceRb::RbLucid#World RDoc\n"
        message << "or http://wiki.github.com/cucumber/cucumber/a-whole-new-world.\n\n"
        super(message)
      end
    end

    # This module is the Ruby implementation of the TDL API.
    class RbLanguage
      include Interface::InterfaceMethods
      attr_reader :current_world, :step_definitions

      # Get the expressions of various I18n translations of TDL keywords.
      # In this case the TDL is based on Gherkin.
      Gherkin::I18n.code_keywords.each do |adverb|
        RbLucid.alias_adverb(adverb)
      end

      def initialize(runtime)
        @runtime = runtime
        @step_definitions = []
        RbLucid.rb_language = self
        @world_proc = @world_modules = nil
        @assertions_module = find_best_assertions_module
      end

      def find_best_assertions_module
        begin
          ::RSpec::Matchers
        rescue NameError
          # RSpec >=1.2.4
          begin
            options = OpenStruct.new(:diff_format => :unified, :context_lines => 3)
            Spec::Expectations.differ = Spec::Expectations::Differs::Default.new(options)
            ::Spec::Matchers
          rescue NameError
            ::Test::Unit::Assertions
          end
        end
      end

      def step_matches(name_to_match, name_to_format)
        @step_definitions.map do |step_definition|
          if(arguments = step_definition.arguments_from(name_to_match))
            StepMatch.new(step_definition, name_to_match, name_to_format, arguments)
          else
            nil
          end
        end.compact
      end

      def snippet_text(code_keyword, step_name, multiline_arg_class, snippet_type = :regexp)
        snippet_class = typed_snippet_class(snippet_type)
        snippet_class.new(code_keyword, step_name, multiline_arg_class).to_s
      end

      def begin_rb_scenario(scenario)
        create_world
        extend_world
        connect_world(scenario)
      end

      def register_rb_hook(phase, tag_expressions, proc)
        add_hook(phase, RbHook.new(self, tag_expressions, proc))
      end

      def register_rb_transform(regexp, proc)
        add_transform(RbTransform.new(self, regexp, proc))
      end

      def register_rb_step_definition(regexp, proc_or_sym, options)
        step_definition = RbStepDefinition.new(self, regexp, proc_or_sym, options)
        @step_definitions << step_definition
        step_definition
      end

      def build_rb_world_factory(world_modules, proc)
        if(proc)
          raise MultipleWorld.new(@world_proc, proc) if @world_proc
          @world_proc = proc
        end
        @world_modules ||= []
        @world_modules += world_modules
      end

      def load_code_file(code_file)
        load File.expand_path(code_file) # This will cause self.add_step_definition, self.add_hook, and self.add_transform to be called from RbLucid
      end

      protected

      def begin_scenario(scenario)
        begin_rb_scenario(scenario)
      end

      def end_scenario
        @current_world = nil
      end

      private

      def create_world
        if(@world_proc)
          @current_world = @world_proc.call
          check_nil(@current_world, @world_proc)
        else
          @current_world = Object.new
        end
      end

      def extend_world
        @current_world.extend(RbWorld)
        @current_world.extend(@assertions_module)
        (@world_modules || []).each do |mod|
          @current_world.extend(mod)
        end
      end

      def connect_world(scenario)
        @current_world.__lucid_runtime = @runtime
        @current_world.__natural_language = scenario.language
      end

      def check_nil(o, proc)
        if o.nil?
          begin
            raise NilWorld.new
          rescue NilWorld => e
            e.backtrace.clear
            e.backtrace.push(proc.backtrace_line("World"))
            raise e
          end
        else
          o
        end
      end

      SNIPPET_TYPES = {
        :regexp => Snippet::Regexp,
        :classic => Snippet::Classic,
        :percent => Snippet::Percent
      }

      def typed_snippet_class(type)
        SNIPPET_TYPES.fetch(type || :regexp)
      end

      def self.cli_snippet_type_options
        SNIPPET_TYPES.keys.sort_by(&:to_s).map do |type|
          SNIPPET_TYPES[type].cli_option_string(type)
        end
      end
    end
  end
end
