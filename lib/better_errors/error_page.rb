require "cgi"
require "json"
require "securerandom"

module BetterErrors
  # @private
  class ErrorPage
    def self.template_path(template_name)
      File.expand_path("../templates/#{template_name}.erb", __FILE__)
    end

    def self.template(template_name)
      Erubis::EscapedEruby.new(File.read(template_path(template_name)))
    end

    attr_reader :exception, :env, :repls

    def initialize(exception, env)
      @exception = RaisedException.new(exception)
      @env = env
      @start_time = Time.now.to_f
      @repls = []
    end

    def id
      @id ||= SecureRandom.hex(8)
    end

    def render(template_name = "main")
      self.class.template(template_name).result binding
    end

    def do_variables(opts)
      index = opts["index"].to_i
      @frame = backtrace_frames[index]
      @var_start_time = Time.now.to_f
      { html: render("variable_info") }
    end

    def do_eval(opts)
      index = opts["index"].to_i
      code = opts["source"]

      unless binding = backtrace_frames[index].frame_binding
        return { error: "REPL unavailable in this stack frame" }
      end

      result, prompt, prefilled_input =
        (@repls[index] ||= REPL.provider.new(binding)).send_input(code)

      { result: result,
        prompt: prompt,
        prefilled_input: prefilled_input,
        highlighted_input: CodeRay.scan(code, :ruby).div(wrap: nil) }
    end

    def backtrace_frames
      exception.backtrace
    end

    def exception_type
      exception.type
    end

    def exception_message
      exception.message.lstrip
    end

    def application_frames
      backtrace_frames.select(&:application?)
    end

    def first_frame
      application_frames.first || backtrace_frames.first
    end

  private
    def editor_url(frame)
      BetterErrors.editor[frame.filename, frame.line]
    end

    def rack_session
      env['rack.session']
    end

    def rails_params
      env['action_dispatch.request.parameters']
    end

    def uri_prefix
      env["SCRIPT_NAME"] || ""
    end

    def request_path
      env["PATH_INFO"]
    end

    def html_formatted_code_block(frame)
      CodeFormatter::HTML.new(frame.filename, frame.line).output
    end

    def text_formatted_code_block(frame)
      CodeFormatter::Text.new(frame.filename, frame.line).output
    end

    def text_heading(char, str)
      str + "\n" + char*str.size
    end

    def inspect_value(obj)
      inspect_raw_value(obj)
    rescue NoMethodError
      "<span class='unsupported'>(object doesn't support inspect)</span>"
    rescue Exception => e
      "<span class='unsupported'>(exception #{CGI.escapeHTML(e.class.to_s)} was raised in inspect)</span>"
    end

    def inspect_raw_value(obj)
      value = CGI.escapeHTML(obj.inspect)

      if !BetterErrors.maximum_variable_inspect_size.nil? && value.length > BetterErrors.maximum_variable_inspect_size
        "<span class='unsupported'>(object too large - modify #{CGI.escapeHTML(obj.class.to_s)}#inspect or raise BetterErrors.maximum_variable_inspect_size)</span>"
      else
        value
      end
    end
  end
end
