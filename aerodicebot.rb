#!/usr/bin/env ruby

require 'logger'
require 'rack'
require 'telegram/bot'
require 'json'

# TODO add recipe to favorites (with notes)

class Recipe
  attr_accessor :coffee_g, :water_ml, :grind, :brew_temp, :brew_time, :inverted, :bloom_time, :bloom_ml, :stirs

  def initialize(params = {})
    @coffee_g = params.fetch(:coffee_g, 0)
    @water_ml = params.fetch(:water_ml, 0)
    @grind = params.fetch(:grind, 'medium')
    @brew_temp = params.fetch(:brew_temp, 0)
    @brew_time = params.fetch(:brew_time, 0)
    @inverted = params.fetch(:inverted, false)
    @bloom_time = params.fetch(:bloom_time, 0)
    @bloom_ml = params.fetch(:bloom_ml, 0)
    @stirs = params.fetch(:stirs, 0)
  end

  def to_json
    {
      coffee_g: @coffee_g,
      water_ml: @water_ml,
      grind: @grind,
      brew_temp: @brew_temp,
      brew_time: @brew_time,
      inverted: @inverted,
      bloom_time: @bloom_time,
      bloom_ml: @bloom_ml,
      stirs: @stirs
    }.to_json
  end

  def to_markdown
    # TODO ERB or other template
    # TODO stirs - clockwise or counter-clockwise
    recipe = [ "Heat *#{@water_ml}* ml of water to *#{@brew_temp}*°C" ]
    recipe.push "Grind *#{@coffee_g}* g of coffee to *#{@grind}* grind"
    if @inverted
      recipe.push "Invert the aeropress"
    else
      recipe.push "Place the aeropress normally, with the rinsed filter and cap on"
    end
    recipe.push "Pour in the ground coffee"
    recipe.push "Add *#{@bloom_ml}* ml of water and wait *#{@bloom_time}* s for the coffee to bloom"
    recipe.push "Add remaining *#{@water_ml-@bloom_ml}* ml of water"
    recipe.push "Stir *#{@stirs}* #{ @stirs == 1 ? 'time' : 'times' } clockwise" if @stirs > 0
    recipe.push "Wait *#{@brew_time}* s to brew"
    recipe.push "Wet the paper filter, and put the cap on. Place the mug upside-down on the aeropress and invert them" if @inverted
    recipe.push "Push."

    recipe.join("\n")
  end
end

class Aerodice
  COFFEE_TO_WATER_RATIO = [
    { coffee: 23, water: 200 },
    { coffee: 18, water: 250 },
    { coffee: 15, water: 250 },
    { coffee: 12, water: 200 }
  ]

  GRIND_TO_BREWTIME_RATIO = [
    { grind: 'fine',    time: 60 },
    { grind: 'medium',  time: 90 },
    { grind: 'coarse',  time: 120 }
  ]

  BLOOM_SECONDS = [20, 30, 40]
  BLOOM_WATER_G = [30, 60]
  BREW_TEMP_C = [80, 85, 90, 95]
  CLOCKWISE_STIR_TIMES = [0, 1, 2]

  def self.random_recipe
    # TODO separate generation and formatting
    coffee_to_water = COFFEE_TO_WATER_RATIO.sample
    grind_to_brewtime = GRIND_TO_BREWTIME_RATIO.sample

    bloom_seconds = BLOOM_SECONDS.sample
    bloom_ml = BLOOM_WATER_G.sample
    brew_temp = BREW_TEMP_C.sample
    stirs = CLOCKWISE_STIR_TIMES.sample

    inverted = [ true, false ].sample

    Recipe.new(
      :coffee_g => coffee_to_water[:coffee],
      :water_ml => coffee_to_water[:water],
      :grind => grind_to_brewtime[:grind],
      :brew_temp => brew_temp,
      :brew_time => grind_to_brewtime[:time],
      :inverted => inverted,
      :bloom_time => bloom_seconds,
      :bloom_ml => bloom_ml,
      :stirs => stirs
    )
  end
end

$logger = Logger.new(STDOUT)

class WebhooksController < Telegram::Bot::UpdatesController
  def message(message)
    $logger.debug('"message" called with: ')
    $logger.debug("message: " + message.to_json) if message
    $logger.debug("from: " + from.to_json) if from
    $logger.debug("chat: " + chat.to_json) if chat
  end

  def start!(*)
    $logger.debug('/start called with: ')
    $logger.debug("from: " + from.to_json) if from
    $logger.debug("chat: " + chat.to_json) if chat
    respond_with :message, text: 'Hey there! For a random aeropress recipe, do a /roll'
  end

  def roll!(*)
    $logger.debug('/roll called with: ')
    $logger.debug("from: " + from.to_json) if from
    $logger.debug("chat: " + chat.to_json) if chat
    respond_with :message, parse_mode: :Markdown, text: Aerodice.random_recipe.to_markdown
  end
end

class AerodiceBot
  def initialize(params = {})
    @webhook_url = params.fetch(:webhook_url)
    @tg_bot_token = params.fetch(:tg_bot_token)
    bot = Telegram::Bot::Client.new(@tg_bot_token)

    webhook_info = bot.get_webhook_info

    $logger.info("Setting webhook URL to '#{@webhook_url}'")
    bot.delete_webhook
    bot.set_webhook(url: @webhook_url)

    @app = Rack::Builder.new do
      map "/tgbot" do
        run Telegram::Bot::Middleware.new(bot, WebhooksController)
      end
    end
  end

  def call(env)
    @app.call(env)
  end
end
