# frozen_string_literal: true

require 'discordrb/bot'
require 'discordrb/data'
require 'discordrb/commands/parser'
require 'discordrb/commands/events'
require 'discordrb/commands/container'
require 'discordrb/commands/rate_limiter'

# Specialized bot to run commands

module Discordrb::Commands
  # Bot that supports commands and command chains
  class CommandBot < Discordrb::Bot
    # @return [Hash] this bot's attributes.
    attr_reader :attributes

    # @return [String] the prefix commands are triggered with.
    attr_reader :prefix

    include CommandContainer

    # Creates a new CommandBot and logs in to Discord.
    # @param attributes [Hash] The attributes to initialize the CommandBot with.
    # @see {Discordrb::Bot#initialize} for other attributes that should be used to create the underlying regular bot.
    # @option attributes [String, Array<String>, #call] :prefix The prefix that should trigger this bot's commands. It
    #   can be:
    #
    #   * Any string (including the empty string). This has the effect that if a message starts with the prefix, the
    #     prefix will be stripped and the rest of the chain will be parsed as a command chain. Note that it will be
    #     literal - if the prefix is "hi" then the corresponding trigger string for a command called "test" would be
    #     "hitest". Don't forget to put spaces in if you need them!
    #   * An array of prefixes. Those will behave similarly to setting one string as a prefix, but instead of only one
    #     string, any of the strings in the array can be used.
    #   * Something Proc-like (responds to :call) that takes a string as an argument (the message) and returns either
    #     the command chain in raw form or `nil` if the given string shouldn't be parsed. This can be used to make more
    #     complicated dynamic prefixes, or even something else entirely (suffixes, or most adventurous, infixes).
    # @option attributes [true, false] :advanced_functionality Whether to enable advanced functionality (very powerful
    #   way to nest commands into chains, see https://github.com/meew0/discordrb/wiki/Commands#command-chain-syntax
    #   for info. Default is false.
    # @option attributes [Symbol, Array<Symbol>, false] :help_command The name of the command that displays info for
    #   other commands. Use an array if you want to have aliases. Default is "help". If none should be created, use
    #   `false` as the value.
    # @option attributes [String] :command_doesnt_exist_message The message that should be displayed if a user attempts
    #   to use a command that does not exist. If none is specified, no message will be displayed. In the message, you
    #   can use the string '%command%' that will be replaced with the name of the command.
    # @option attributes [String] :no_permission_message The message to be displayed when `NoPermission` error is raised.
    # @option attributes [true, false] :spaces_allowed Whether spaces are allowed to occur between the prefix and the
    #   command. Default is false.
    # @option attributes [String] :previous Character that should designate the result of the previous command in
    #   a command chain (see :advanced_functionality). Default is '~'.
    # @option attributes [String] :chain_delimiter Character that should designate that a new command begins in the
    #   command chain (see :advanced_functionality). Default is '>'.
    # @option attributes [String] :chain_args_delim Character that should separate the command chain arguments from the
    #   chain itself (see :advanced_functionality). Default is ':'.
    # @option attributes [String] :sub_chain_start Character that should start a sub-chain (see
    #   :advanced_functionality). Default is '['.
    # @option attributes [String] :sub_chain_end Character that should end a sub-chain (see
    #   :advanced_functionality). Default is ']'.
    # @option attributes [String] :quote_start Character that should start a quoted string (see
    #   :advanced_functionality). Default is '"'.
    # @option attributes [String] :quote_end Character that should end a quoted string (see
    #   :advanced_functionality). Default is '"'.
    def initialize(attributes = {})
      super(
        log_mode: attributes[:log_mode],
        token: attributes[:token],
        application_id: attributes[:application_id],
        type: attributes[:type],
        name: attributes[:name],
        fancy_log: attributes[:fancy_log],
        suppress_ready: attributes[:suppress_ready],
        parse_self: attributes[:parse_self],
        shard_id: attributes[:shard_id],
        num_shards: attributes[:num_shards])

      @prefix = attributes[:prefix]
      @attributes = {
        # Whether advanced functionality such as command chains are enabled
        advanced_functionality: attributes[:advanced_functionality].nil? ? false : attributes[:advanced_functionality],

        # The name of the help command (that displays information to other commands). False if none should exist
        help_command: attributes[:help_command].is_a?(FalseClass) ? nil : (attributes[:help_command] || :help),

        # The message to display for when a command doesn't exist, %command% to get the command name in question and nil for no message
        # No default value here because it may not be desired behaviour
        command_doesnt_exist_message: attributes[:command_doesnt_exist_message],

        # The message to be displayed when `NoPermission` error is raised.
        no_permission_message: attributes[:no_permission_message],

        # Spaces allowed between prefix and command
        spaces_allowed: attributes[:spaces_allowed].nil? ? false : attributes[:spaces_allowed],

        # All of the following need to be one character
        # String to designate previous result in command chain
        previous: attributes[:previous] || '~',

        # Command chain delimiter
        chain_delimiter: attributes[:chain_delimiter] || '>',

        # Chain argument delimiter
        chain_args_delim: attributes[:chain_args_delim] || ':',

        # Sub-chain starting character
        sub_chain_start: attributes[:sub_chain_start] || '[',

        # Sub-chain ending character
        sub_chain_end: attributes[:sub_chain_end] || ']',

        # Quoted mode starting character
        quote_start: attributes[:quote_start] || '"',

        # Quoted mode ending character
        quote_end: attributes[:quote_end] || '"'
      }

      @permissions = {
        roles: {},
        users: {}
      }

      return unless @attributes[:help_command]
      command(@attributes[:help_command], max_args: 1, description: 'Shows a list of all the commands available or displays help for a specific command.', usage: 'help [command name]') do |event, command_name|
        if command_name
          command = @commands[command_name.to_sym]
          return "The command `#{command_name}` does not exist!" unless command
          desc = command.attributes[:description] || '*No description available*'
          usage = command.attributes[:usage]
          parameters = command.attributes[:parameters]
          result = "**`#{command_name}`**: #{desc}"
          result += "\nUsage: `#{usage}`" if usage
          if parameters
            result += "\nAccepted Parameters:"
            parameters.each { |p| result += "\n    `#{p}`" }
          end
          result
        else
          available_commands = @commands.values.reject { |c| !c.attributes[:help_available] }
          case available_commands.length
          when 0..5
            available_commands.reduce "**List of commands:**\n" do |memo, c|
              memo + "**`#{c.name}`**: #{c.attributes[:description] || '*No description available*'}\n"
            end
          when 5..50
            (available_commands.reduce "**List of commands:**\n" do |memo, c|
              memo + "`#{c.name}`, "
            end)[0..-3]
          else
            event.user.pm(available_commands.reduce("**List of commands:**\n") { |a, e| a + "`#{e.name}`, " })[0..-3]
            'Sending list in PM!'
          end
        end
      end
    end

    # Executes a particular command on the bot. Mostly useful for internal stuff, but one can never know.
    # @param name [Symbol] The command to execute.
    # @param event [CommandEvent] The event to pass to the command.
    # @param arguments [Array<String>] The arguments to pass to the command.
    # @param chained [true, false] Whether or not it should be executed as part of a command chain. If this is false,
    #   commands that have chain_usable set to false will not work.
    # @return [String, nil] the command's result, if there is any.
    def execute_command(name, event, arguments, chained = false)
      debug("Executing command #{name} with arguments #{arguments}")
      command = @commands[name]
      unless command
        event.respond @attributes[:command_doesnt_exist_message].gsub('%command%', name.to_s) if @attributes[:command_doesnt_exist_message]
        return
      end
      if permission?(event.author, command.attributes[:permission_level], event.server) &&
         required_permissions?(event.author, command.attributes[:required_permissions], event.channel) &&
         required_roles?(event.author, command.attributes[:required_roles])
        event.command = command
        result = command.call(event, arguments, chained)
        stringify(result)
      else
        event.respond command.attributes[:permission_message].gsub('%name%', name.to_s) if command.attributes[:permission_message]
        nil
      end
    rescue Discordrb::Errors::NoPermission
      event.respond @attributes[:no_permission_message] unless @attributes[:no_permission_message].nil?
      raise
    end

    # Executes a command in a simple manner, without command chains or permissions.
    # @param chain [String] The command with its arguments separated by spaces.
    # @param event [CommandEvent] The event to pass to the command.
    # @return [String, nil] the command's result, if there is any.
    def simple_execute(chain, event)
      return nil if chain.empty?
      args = chain.split(' ')
      execute_command(args[0].to_sym, event, args[1..-1])
    end

    # Sets the permission level of a user
    # @param id [Integer] the ID of the user whose level to set
    # @param level [Integer] the level to set the permission to
    def set_user_permission(id, level)
      @permissions[:users][id] = level
    end

    # Sets the permission level of a role - this applies to all users in the role
    # @param id [Integer] the ID of the role whose level to set
    # @param level [Integer] the level to set the permission to
    def set_role_permission(id, level)
      @permissions[:roles][id] = level
    end

    # Check if a user has permission to do something
    # @param user [User] The user to check
    # @param level [Integer] The minimum permission level the user should have (inclusive)
    # @param server [Server] The server on which to check
    # @return [true, false] whether or not the user has the given permission
    def permission?(user, level, server)
      determined_level = server.nil? ? 0 : user.roles.reduce(0) do |memo, role|
        [@permissions[:roles][role.id] || 0, memo].max
      end
      [@permissions[:users][user.id] || 0, determined_level].max >= level
    end

    private

    # Internal handler for MESSAGE_CREATE that is overwritten to allow for command handling
    def create_message(data)
      message = Discordrb::Message.new(data, self)
      return if message.from_bot? && !@should_parse_self

      unless message.author
        Discordrb::LOGGER.warn("Received a message (#{message.inspect}) with nil author! Ignoring, please report this if you can")
        return
      end

      event = CommandEvent.new(message, self)

      chain = trigger?(message.content)
      return unless chain

      # Don't allow spaces between the prefix and the command
      if chain.start_with?(' ') && !@attributes[:spaces_allowed]
        debug('Chain starts with a space')
        return
      end

      if chain.strip.empty?
        debug('Chain is empty')
        return
      end

      execute_chain(chain, event)
    end

    # Check whether a message should trigger command execution, and if it does, return the raw chain
    def trigger?(message)
      if @prefix.is_a? String
        standard_prefix_trigger(message, @prefix)
      elsif @prefix.is_a? Array
        @prefix.map { |e| standard_prefix_trigger(message, e) }.reduce { |a, e| a || e }
      elsif @prefix.respond_to? :call
        @prefix.call(message)
      end
    end

    def standard_prefix_trigger(message, prefix)
      return nil unless message.start_with? prefix
      message[prefix.length..-1]
    end

    def required_permissions?(member, required, channel = nil)
      required.reduce(true) do |a, action|
        a && member.permission?(action, channel)
      end
    end

    def required_roles?(member, required)
      if required.is_a? Array
        required.all? do |role|
          member.role?(role)
        end
      else
        member.role?(role)
      end
    end

    def execute_chain(chain, event)
      t = Thread.new do
        @event_threads << t
        Thread.current[:discordrb_name] = "ct-#{@current_thread += 1}"
        begin
          debug("Parsing command chain #{chain}")
          result = @attributes[:advanced_functionality] ? CommandChain.new(chain, self).execute(event) : simple_execute(chain, event)
          result = event.drain_into(result)

          if event.file
            event.send_file(event.file, caption: result)
          else
            event.respond result unless result.nil? || result.empty?
          end
        rescue => e
          log_exception(e)
        ensure
          @event_threads.delete(t)
        end
      end
    end

    # Turns the object into a string, using to_s by default
    def stringify(object)
      return '' if object.is_a? Discordrb::Message

      object.to_s
    end
  end
end
