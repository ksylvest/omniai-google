# OmniAI::Google

[![LICENSE](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/ksylvest/omniai-google/blob/main/LICENSE)
[![RubyGems](https://img.shields.io/gem/v/omniai-google)](https://rubygems.org/gems/omniai-google)
[![GitHub](https://img.shields.io/badge/github-repo-blue.svg)](https://github.com/ksylvest/omniai-google)
[![Yard](https://img.shields.io/badge/docs-site-blue.svg)](https://omniai-google.ksylvest.com)
[![CircleCI](https://img.shields.io/circleci/build/github/ksylvest/omniai-google)](https://circleci.com/gh/ksylvest/omniai-google)

A Google implementation of the [OmniAI](https://github.com/ksylvest/omniai) APIs.

## Installation

```sh
gem install omniai-google
```

## Usage

### Client

A client is setup as follows if `ENV['GOOGLE_API_KEY']` exists:

```ruby
client = OmniAI::Google::Client.new
```

A client may also be passed the following options:

- `api_key` (required - default is `ENV['GOOGLE_API_KEY']`)
- `credentials` (optional)
- `host` (optional)
- `version` (optional - options are `v1` or `v1beta`)

### Configuration

Vertex AI and Google AI offer different options for interacting w/ Google's AI APIs. Checkout the [Vertex AI and Google AI differences](https://cloud.google.com/vertex-ai/generative-ai/docs/overview#how-gemini-vertex-different-gemini-aistudio) to determine which option best fits your requirements.

#### Configuration w/ Google AI

If using Gemini simply provide an `api_key`:

```ruby
OmniAI::Google.configure do |config|
  config.api_key = 'sk-...' # defaults is `ENV['GOOGLE_API_KEY']`
end
```

#### Configuration w/ Vertex AI

If using Vertex supply the `credentials`, `host`, `location_id` and `project_id`:

```ruby
OmniAI::Google.configure do |config|
  config.credentials = File.open("./credentials.json") # default is `ENV['GOOGLE_CREDENTIALS_PATH']` / `ENV['GOOGLE_CREDENTIALS_JSON']`
  config.host = 'https://us-east4-aiplatform.googleapis.com' # default is `ENV['GOOGLE_HOST']`
  config.location_id = 'us-east4' # defaults is `ENV['GOOGLE_LOCATION_ID']`
  config.project_id = '...' # defaults is `ENV['GOOGLE_PROJECT_ID']`
end
```

Credentials may be configured using:

1. A `File` / `String` / `Pathname`.
2. Assigning `ENV['GOOGLE_CREDENTIALS_PATH']` as the path to the `credentials.json`.
3. Assigning `ENV['GOOGLE_CREDENTIALS_JSON']` to the contents of `credentials.json`.

### Chat

A chat completion is generated by passing in a simple text prompt:

```ruby
completion = client.chat('Tell me a joke!')
completion.text # 'Why did the chicken cross the road? To get to the other side.'
```

A chat completion may also be generated by using the prompt builder:

```ruby
completion = client.chat do |prompt|
  prompt.system('Your are an expert in geography.')
  prompt.user('What is the capital of Canada?')
end
completion.text # 'The capital of Canada is Ottawa.'
```

#### Model

`model` takes an optional string (default is `gemini-1.5-pro`):

```ruby
completion = client.chat('How fast is a cheetah?', model: OmniAI::Google::Chat::Model::GEMINI_FLASH)
completion.text # 'A cheetah can reach speeds over 100 km/h.'
```

[Google API Reference `model`](https://cloud.google.com/vertex-ai/generative-ai/docs/learn/model-versioning#gemini-model-versions)

#### Temperature

`temperature` takes an optional float between `0.0` and ` 2.0`:

```ruby
completion = client.chat('Pick a number between 1 and 5', temperature: 2.0)
completion.text # '3'
```

[Google API Reference `temperature`](https://ai.google.dev/api/rest/v1/GenerationConfig)

#### Stream

`stream` takes an optional a proc to stream responses in real-time chunks instead of waiting for a complete response:

```ruby
stream = proc do |chunk|
  print(chunk.text) # 'Better', 'three', 'hours', ...
end
client.chat('Be poetic.', stream:)
```

### Upload

An upload is especially useful when processing audio / image / video / text files. To use:

```ruby
CAT_URL = 'https://images.unsplash.com/photo-1472491235688-bdc81a63246e?fm=jpg'
DOG_URL = 'https://images.unsplash.com/photo-1517849845537-4d257902454a?fm=jpg'

begin
  cat_upload = client.upload(CAT_URL)
  dog_upload = client.upload(DOG_URL)

  completion = client.chat(stream: $stdout) do |prompt|
    prompt.user do |message|
      message.text 'What are these photos of?'
      message.url(cat_upload.uri, cat_upload.mime_type)
      message.url(dog_upload.uri, dog_upload.mime_type)
    end
  end
ensure
  cat_upload.delete!
  dog_upload.delete!
end
```

[Google API Reference `stream`](https://ai.google.dev/gemini-api/docs/api-overview#stream)

### Embed

Text can be converted into a vector embedding for similarity comparison usage via:

```ruby
response = client.embed('The quick brown fox jumps over a lazy dog.')
response.embedding # [0.0, ...]
```
