# frozen_string_literal: true

# Agent for the MRKL chain
module Boxcars
  # A Train using the zero-shot react method.
  class ZeroShot < Train
    attr_reader :boxcars, :observation_prefix, :engine_prefix

    # @param boxcars [Array<Boxcars::Boxcar>] The boxcars to run.
    # @param engine [Boxcars::Engine] The engine to use for this train.
    # @param name [String] The name of the train. Defaults to 'Zero Shot'.
    # @param description [String] The description of the train. Defaults to 'Zero Shot Train'.
    # @param prompt [Boxcars::Prompt] The prompt to use. Defaults to the built-in prompt.
    def initialize(boxcars:, engine: nil, name: 'Zero Shot', description: 'Zero Shot Train', prompt: nil)
      @observation_prefix = 'Observation: '
      @engine_prefix = 'Thought:'
      prompt ||= my_prompt
      super(engine: engine, boxcars: boxcars, prompt: prompt, name: name, description: description)
    end

    # @return Hash The additional variables for this boxcar.
    def prediction_additional
      { boxcar_names: boxcar_names, boxcar_descriptions: boxcar_descriptions }.merge super
    end

    # Extract the boxcar and input from the engine output.
    # @param text [String] The output from the engine.
    # @return [Array<Boxcars::Boxcar, String>] The boxcar and input.
    def extract_boxcar_and_input(text)
      get_action_and_input engine_output: text
    end

    private

    # the final answer action string
    FINAL_ANSWER_ACTION = "Final Answer:"

    # Parse out the action and input from the engine output.
    # @param engine_output [String] The output from the engine.
    # @return [Array<String>] The action and input.
    def get_action_and_input(engine_output:)
      # NOTE: if you're specifying a custom prompt for the ZeroShotAgent,
      #   you will need to ensure that it meets the following Regex requirements.
      #   The string starting with "Action:" and the following string starting
      #   with "Action Input:" should be separated by a newline.

      is_engine_processing_final_answer = engine_output.include? FINAL_ANSWER_ACTION

      unless is_engine_processing_final_answer
        # processing a thought/action/action_input/observation sequence and their inputs:
        # the thought should be the frist line here if it doesn't start with "Action:"
        thought = engine_output.split(/\n+/).reject(&:empty?).first
        Boxcars.debug("Thought: #{thought}", :yellow)

        regex = /Action: (?<action>.+?)\n+Action Input:(?<action_input>.+)/m
        match = regex.match engine_output

        # we have an unexpected output from the engine
        unless match
          return [:error, "You gave me an improperly fomatted answer - try again. For example, if you know the final anwwer, " \
                          "start with #{FINAL_ANSWER_ACTION.inspect}"]
        end

        action = match[:action].strip
        action_input = match[:action_input].strip.delete_prefix('"').delete_suffix('"')
        # TODO: move to coloured debug output
        puts "ACTION: #{action}"
        puts "ACTION INPUT: #{action_input}"
        [action, action_input]
      else
        # processing final answer:
        answer = engine_output.split(FINAL_ANSWER_ACTION).last.strip
        Result.new status: :ok, answer: answer, explanation: engine_output
      end
    end

    CTEMPLATE = [
      syst(
        <<-PROMPT.gsub /^ {10}/, ""
          You are an AI Assistant and you are helping a user break down a series of tasks based on a reasoning process. The reasoning starts with a user input named Question which could be a Question or a request to execute an action. Then you are presented with a Thought, which is how you think you should resolve the question/input. In the Thought section you should think what do you need from the various actions you have access to. Action, the name of the action you will execute. Action Input, the parameters of the action. Observation, the result of the action, note that the observation should be different than your Thought. Usually Observation contains the Action Inputs from the previous Action.
          Note that the Thought/Action/Action Input/Observation sequence can repeat N times.

          Answer the following questions as best you can. You have access to the following actions:
          %<boxcar_descriptions>s

          Use the following format:
          Question: the input question you must answer
          Thought: you should always think about what to do
          Action: the action to take, should be one from this list: %<boxcar_names>s
          Action Input: the input to the action
          Observation: the result of the action
          ...

          <<< this Thought/Action/Action Input/Observation sequence can repeat N times, make sure all actions are prepended with "Action: " >>>

          ...
          Thought: I know the final answer
          Final Answer: the final answer to the original input question
          Next Actions: Up to 3 logical suggested next questions for the user to ask after getting this answer.

          Remember to start a line with "Final Answer:" to give me the final answer.

          Begin!
        PROMPT
      ),
      user("Question: %<input>s"),
      assi("Thought: %<agent_scratchpad>s")
    ].freeze

    def boxcar_names
      @boxcar_names ||= "[#{boxcars.map(&:name).join(', ')}]"
    end

    def boxcar_descriptions
      @boxcar_descriptions ||= boxcars.map { |boxcar| "#{boxcar.name}: #{boxcar.description}" }.join("\n")
    end

    # The prompt to use for the train.
    def my_prompt
      @conversation ||= Conversation.new(lines: CTEMPLATE)
      @my_prompt ||= ConversationPrompt.new(
        conversation: @conversation,
        input_variables: [:input],
        other_inputs: [:boxcar_names, :boxcar_descriptions, :agent_scratchpad],
        output_variables: [:answer])
    end
  end
end
