require 'pry'
require 'tty-spinner'
require 'tty-command'
require 'tty-prompt'
require 'pastel'
require 'timeout'
require 'logger'
require 'yaml'

require_relative '../lib/gist_wrapper/constants'
require_relative '../lib/gist_wrapper'

trap('INT') do
  puts ''
  puts 'You pressed ctrl-c'
  exit
end

class Setup

  ENV_NAME = 'GIST_TOKEN'.freeze

  def self.run
    begin
      sleep 1
      instance = Setup.new
      instance.title
      instance.install
      unless GistWrapper.test_token
        options = instance.options
        prompt = options.keys[options.values.index(instance.select_prompt)]
        instance.send prompt
      end
      instance.leave
    rescue TTY::Reader::InputInterrupt
      puts ''
      puts 'You press ctrl-c'
      exit
    end
  end

  def title
    puts '-----------------------------------------------------------'
    gist =
      '
     ██████╗ ██╗███████╗████████╗
    ██╔════╝ ██║██╔════╝╚══██╔══╝
    ██║  ███╗██║███████╗   ██║
    ██║   ██║██║╚════██║   ██║
    ╚██████╔╝██║███████║   ██║
     ╚═════╝ ╚═╝╚══════╝   ╚═╝'
    wrapper = 'wrapper'
    puts "#{printer.cyan(gist)} #{wrapper}"
    puts "Version (#{GistWrapper::VERSION})"
    puts '-----------------------------------------------------------'
  end

  def install
    Timeout.timeout(60) do
      TTY::Spinner.new('[:spinner] Installing gems', format: :dots, clear: true).run do
        logger = Logger.new('setup.log')
        TTY::Command.new(output: logger).run 'bundle install'
      end
      TTY::Spinner.new('[:spinner] Updating gems', format: :dots, clear: true).run do
        logger = Logger.new('setup.log')
        TTY::Command.new(output: logger).run 'bundle update'
      end
    end
  end

  def select_prompt
    puts printer.black.on_bright_magenta('     To run tests you need to provide an auth token.       ')
    puts printer.black.on_bright_magenta('       It needs to be set in the token.yaml file           ')
    puts printer.black.on_bright_magenta('               You can do this yourself                    ')
    puts printer.black.on_bright_magenta('                         here:                             ')
    puts printer.black.on_bright_magenta('            https://github.com/settings/tokens             ')
    puts printer.black.on_bright_magenta('               Or I can do it for you                      ')

    question = printer.cyan('What would you like to do?')
    prompt.select(question, options.values)
  end

  def options
    {
      prompt_token: 'I have a token, set it for me',
      prompt_generate: 'Generate my token and set it for me',
      exit: 'I will do it myself'
    }
  end

  def prompt_token
    token = loop do
      t = prompt.ask('40 char Token for https://github.com:')
      break t if test_token t
      puts 'The token you provided is not valid. Please try again'
    end
    set_gist_token(token)
  end

  def prompt_generate
    wait_gem('octokit')
    loop do
      if login
        puts 'login successful'
        break
      else
        puts 'Invalid username or password'
        puts 'Please try again'
      end
    end
    token = generate_token.token
    puts "#{printer.black.on_bright_blue('Your token:')}#{printer.black.on_bright_green.bold(token)}"
    set_gist_token(token)
  end

  def leave
    puts printer.green('setup successful')
    puts printer.green.bold('DONE!')
  end

  def login
    begin
      username = prompt.ask('Username for https://github.com: ' )
      password = prompt.mask("Password for #{username}: " )
      spinner = TTY::Spinner.new('[:spinner] Signing in...', format: :dots, clear: true)
      spinner.auto_spin
      sleep 1
      client(username, password).user.login
      @username = username
      @password = password
      spinner.stop
      true
    rescue Octokit::Unauthorized
      spinner.stop
      false
    end
  end

  def client(username = '', password = '')
    Octokit::Client.new(
      login: username,
      password: password
    )
  end

  # returns Github oauth token see https://github.com/octokit/octokit.rb#oauth-access-tokens
  def generate_token
    spinner = TTY::Spinner.new('[:spinner] Generating token...', format: :dots, clear: true)
    spinner.auto_spin
    token = client(@username, @password).create_authorization(
      scopes: ['gist'], note: "Gist Token made at #{Time.now}"
    )
    spinner.stop
    token
  end

  def set_gist_token(token)
    File.open(GistWrapper::YAML_PATH, 'w') {|f| f.write({'token': token}.to_yaml) }
    puts 'Your token has been written to token.yaml'
  end

  def printer
    @printer ||= Pastel.new
  end

  def prompt
    @prompt ||= TTY::Prompt.new
  end

  def test_token(token)
    #TODO: spinner are not working
    spinner = TTY::Spinner.new("[:spinner] Checking token...", format: :dots, clear: true)
    spinner.auto_spin
    ret = begin
      client = Octokit::Client.new access_token: token
      client.login
      true
    rescue Octokit::Unauthorized
      false
    end
    spinner.stop
    ret
  end

  def wait_gem(gem)
    TTY::Spinner.new("[:spinner] Loading #{gem}...", format: :dots, clear: true).run do
      sleep 3
      2.times do
        begin
          send(:require, gem.to_s)
        rescue
          sleep 5
        end
      end
    end
  end

end
