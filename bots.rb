#!/usr/bin/env ruby

require 'twitter_ebooks'
require 'dotenv'
Dotenv.load(".env")
include Ebooks

# ALL_BOTS = ['EBOOKS', 'CELESTROGEN']

ROBOT_ID = "ebooks" # Prefer not to talk to other robots

# ALESSIA EBOOKS KEYS
CONSUMER_KEY = ENV['EBOOKS_CONSUMER_KEY']
CONSUMER_SECRET = ENV['EBOOKS_CONSUMER_SECRET']
OAUTH_TOKEN = ENV['EBOOKS_OAUTH_TOKEN']
OAUTH_TOKEN_SECRET = ENV['EBOOKS_OAUTH_TOKEN_SECRET']
TWITTER_USERNAME = "alessia_ebooks"

# CELESTROGEN EBOOKS KEYS
CELESTROGEN_CONSUMER_KEY = ENV['CELESTROGEN_CONSUMER_KEY']
CELESTROGEN_CONSUMER_SECRET = ENV['CELESTROGEN_CONSUMER_SECRET']
CELESTROGEN_OAUTH_TOKEN = ENV['CELESTROGEN_OAUTH_TOKEN']
CELESTROGEN_OAUTH_TOKEN_SECRET = ENV['CELESTROGEN_OAUTH_TOKEN_SECRET']
CELESTROBOT_TWITTER_USERNAME = "celestrobot"

# BAKERBOT EBOOKS KEYS
BAKERBOT_CONSUMER_KEY = ENV['BAKERBOT_CONSUMER_KEY']
BAKERBOT_CONSUMER_SECRET = ENV['BAKERBOT_CONSUMER_SECRET']
BAKERBOT_OAUTH_TOKEN = ENV['BAKERBOT_OAUTH_TOKEN']
BAKERBOT_OAUTH_TOKEN_SECRET = ENV['BAKERBOT_OAUTH_TOKEN_SECRET']
BAKERBOT_TWITTER_USERNAME = "weyoun8inches"


DELAY = 2..30 # Simulated human reply delay range, in seconds
BLACKLIST = [] # users to avoid interaction with
SPECIAL_WORDS = ['singularity', 'world domination'] # Words we like
BANNED_WORDS = ['voldemort', 'evgeny morozov', 'heroku'] # Words we don't want to use

# Track who we've randomly interacted with globally
$have_talked = {}
$banned_words = BANNED_WORDS

# Overwrite the Model#valid_tweet? method to check for banned words
class Ebooks::Model
  def valid_tweet?(tokens, limit)
    tweet = NLP.reconstruct(tokens)
    found_banned = $banned_words.any? do |word|
      re = Regexp.new("\\b#{word}\\b", "i")
      re.match tweet
    end
    tweet.length <= limit && !NLP.unmatched_enclosers?(tweet) && !found_banned
  end
end

class GenBot
  def initialize(bot, modelname, consumer_key, consumer_secret)
    @bot = bot
    @model = nil

    bot.consumer_key = consumer_key
    bot.consumer_secret = consumer_secret

    bot.on_startup do
      @model = Model.load("model/#{modelname}.model")
      @top100 = @model.keywords.top(100).map(&:to_s).map(&:downcase)
      @top50 = @model.keywords.top(20).map(&:to_s).map(&:downcase)
    end

    bot.on_message do |dm|
      bot.delay DELAY do
        bot.reply dm, @model.make_response(dm[:text])
      end
    end

    bot.on_follow do |user|
      bot.delay DELAY do
        bot.follow user[:screen_name]
      end
    end

    bot.on_mention do |tweet, meta|
      # Avoid infinite reply chains
      next if tweet[:user][:screen_name].include?(ROBOT_ID) && rand > 0.05

      author = tweet[:user][:screen_name]
      next if $have_talked.fetch(author, 0) >= 5
      $have_talked[author] = $have_talked.fetch(author, 0) + 1

      tokens = NLP.tokenize(tweet[:text])
      very_interesting = tokens.find_all { |t| @top50.include?(t.downcase) }.length > 2
      special = tokens.find { |t| SPECIAL_WORDS.include?(t) }

      if very_interesting || special
        favorite(tweet)
      end

      reply(tweet, meta)
    end

    bot.on_timeline do |tweet, meta|
      next if tweet[:retweeted_status] || tweet[:text].start_with?('RT')
      author = tweet[:user][:screen_name]
      next if BLACKLIST.include?(author)

      tokens = NLP.tokenize(tweet[:text])

      # We calculate unprompted interaction probability by how well a
      # tweet matches our keywords
      interesting = tokens.find { |t| @top100.include?(t.downcase) }
      very_interesting = tokens.find_all { |t| @top50.include?(t.downcase) }.length > 2
      special = tokens.find { |t| SPECIAL_WORDS.include?(t) }

      if special
        favorite(tweet)
        favd = true # Mark this tweet as favorited

        bot.delay DELAY do
          bot.follow author
        end
      end

      # Any given user will receive at most one random interaction per 12h
      # (barring special cases)
      next if $have_talked[author]
      $have_talked[author] = $have_talked.fetch(author, 0) + 1

      if very_interesting || special
        favorite(tweet) if (rand < 0.5 && !favd) # Don't fav the tweet if we did earlier
        retweet(tweet) if rand < 0.1
        reply(tweet, meta) if rand < 0.1
      elsif interesting
        favorite(tweet) if rand < 0.1
        reply(tweet, meta) if rand < 0.05
      end
    end

    # Reset list of mention recipients every 12 hrs:
    bot.scheduler.every '12h' do
      $have_talked = {}
    end

    # 80% chance to tweet every 2 hours
    bot.scheduler.every '2h' do
      if rand <= 0.8
        bot.tweet @model.make_statement
      end
    end
  end

  def reply(tweet, meta)
    resp = @model.make_response(meta[:mentionless], meta[:limit])
    @bot.delay DELAY do
      @bot.reply tweet, meta[:reply_prefix] + resp
    end
  end

  def favorite(tweet)
    @bot.log "Favoriting @#{tweet[:user][:screen_name]}: #{tweet[:text]}"
    @bot.delay DELAY do
      @bot.twitter.favorite(tweet[:id])
    end
  end

  def retweet(tweet)
    @bot.log "Retweeting @#{tweet[:user][:screen_name]}: #{tweet[:text]}"
    @bot.delay DELAY do
      @bot.twitter.retweet(tweet[:id])
    end
  end
end

def make_bot(bot, modelname, consumer_key, consumer_secret)
  GenBot.new(bot, modelname, consumer_key, consumer_secret)
end

Ebooks::Bot.new(TWITTER_USERNAME) do |bot|
  bot.oauth_token = OAUTH_TOKEN
  bot.oauth_token_secret = OAUTH_TOKEN_SECRET

  make_bot(bot, 'alessbell', CONSUMER_KEY, CONSUMER_SECRET)
end

Ebooks::Bot.new(CELESTROBOT_TWITTER_USERNAME) do |bot|
  bot.oauth_token = CELESTROGEN_OAUTH_TOKEN
  bot.oauth_token_secret = CELESTROGEN_OAUTH_TOKEN_SECRET

  make_bot(bot, 'celestrogen', CELESTROGEN_CONSUMER_KEY, CELESTROGEN_CONSUMER_SECRET)
end

Ebooks::Bot.new(BAKERBOT_TWITTER_USERNAME) do |bot|
  bot.oauth_token = BAKERBOT_OAUTH_TOKEN
  bot.oauth_token_secret = BAKERBOT_OAUTH_TOKEN_SECRET

  make_bot(bot, 'weyoun8inches', BAKERBOT_CONSUMER_KEY, BAKERBOT_CONSUMER_SECRET)
end


# ALL_BOTS.each do |e|
#   Ebooks::Bot.new(TWITTER_USERNAME) do |bot|
#     bot.oauth_token = OAUTH_TOKEN
#     bot.oauth_token_secret = OAUTH_TOKEN_SECRET
#
#     make_bot(bot, TEXT_MODEL_NAME)
#   end
# end
