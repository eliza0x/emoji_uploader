require 'pry'
require 'dotenv'
require 'rmagick'
require 'mechanize'
require 'open-uri'
require 'rest-client'
require 'slack-ruby-client'

Dotenv.load

class SlackTeam
  def initialize(team, email, password)
    @base_url = "https://#{team}.slack.com"
    @agent = Mechanize.new
    page = @agent.get(@base_url)
    login(email, password, page)
  end

  def login(email, password, page)
    res = page.form_with(action: '/') do |form|
      form.field_with(name: 'email').value = email
      form.field_with(name: 'password').value = password
    end.submit

    if res.code != '200'
      puts "[#{res.code}] Login failed."
      return -1
    end
  end

  def download_file(name, url)
    res = RestClient.get(url, { "Authorization" => "Bearer #{ENV['SLACK_TOKEN']}" })

    if res.code == 200
      File.open(name, "wb") do |f|
        f.puts(res.body)
      end
    else
      puts "[#{res.code}] Download failed"
    end
  end

  def resize_file(name)
    # TODO: Use Tempfile
    original = Magick::ImageList.new
    url = open(name)
    original.from_blob(url.read)

    image = original.resize_to_fit(128, 128)
    image.write(name)
  end

  def upload_emoji(file_name, emoji_name)
    @agent.get("#{@base_url}/customize/emoji") do |page|
      if page.body.include?(":#{emoji_name}:")
        puts ":#{emoji_name}: is already exists."
      else
        puts "Uploading :#{emoji_name}:..."
        res = page.form_with(action: '/customize/emoji') do |form|
          form.field_with(name: 'name').value = emoji_name
          form.radiobuttons_with(name: 'mode')[0].check
          form.file_upload_with(name: 'img').file_name = file_name
        end.submit
        puts "Updated :#{emoji_name}:!"
      end
    end
  end
end

slack = SlackTeam.new(ENV['SLACK_TEAM'], ENV['SLACK_EMAIL'], ENV['SLACK_PASS'])

Slack.configure do |config|
  config.token = ENV['SLACK_TOKEN']
  fail "Missing ENV['SLACK_TOKEN']" unless config.token
end

client = Slack::RealTime::Client.new

client.on :hello do
  puts "Successfully connected. Logged in as #{client.self.name} to #{client.team.name}."
end

client.on :close do |_data|
  puts "Disconnecting..."
end

client.on :closed do |_data|
  puts "Client has disconnected successfully."
end

client.on :message do |data|
  # emoji-test or emoji
  if data.channel.match(/C3VM58ZEF|C16N9Q0DC/) && data.file
    file = data.file
    file_name = file.title
    emoji_name = "#{File.basename(file_name, '.*')}"

    begin
      slack.download_file(file_name, file.url_private)
      slack.resize_file(file_name)
      slack.upload_emoji(file_name, emoji_name)
      File.delete(file_name)
      client.message(channel: data.channel, text: "New emoji has been created! :#{emoji_name}:")
    rescue :e
      puts e
      client.message(channel: data.channel, text: "Couldn't add the emoji.")
    end
  end
end

client.start!
