FROM ruby:2.7.3
RUN apt-get update && apt-get install -y \
    locales \
    locales-all \
    libopus-dev \
    ffmpeg \
    libopus0 \
    libsodium-dev
WORKDIR /app
COPY Gemfile /app/
ENV LANG ja_JP.UTF-8
RUN bundle install
COPY discord_voicebot.rb /app/
COPY voicevox.rb /app/
COPY deepl_trans.rb /app/
CMD ["bundle", "exec", "ruby", "discord_voicebot.rb"]