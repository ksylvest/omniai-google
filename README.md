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

**Note for Transcription**: When using transcription features, ensure your service account has the necessary permissions for Google Cloud Speech-to-Text API and Google Cloud Storage (for automatic file uploads). See the [GCS Setup](#gcs-setup-for-transcription) section below for detailed configuration.

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

### Transcribe

Audio files can be transcribed using Google's Speech-to-Text API. The implementation automatically handles both synchronous and asynchronous recognition based on file size and model type.

#### Basic Usage

```ruby
# Transcribe a local audio file
result = client.transcribe("path/to/audio.mp3")
result.text # "Hello, this is the transcribed text..."

# Transcribe with specific model
result = client.transcribe("path/to/audio.mp3", model: "latest_long")
result.text # "Hello, this is the transcribed text..."
```

#### Multi-Language Detection

The transcription automatically detects multiple languages when no specific language is provided:

```ruby
# Auto-detect English and Spanish
result = client.transcribe("bilingual_audio.mp3", model: "latest_long")
result.text # "Hello, how are you? Hola, ¿cómo estás?"

# Specify expected languages explicitly
result = client.transcribe("audio.mp3", language: ["en-US", "es-US"], model: "latest_long")
```

#### Detailed Transcription with Timestamps

Use `VERBOSE_JSON` format to get detailed timing information, confidence scores, and language detection per segment:

```ruby
result = client.transcribe("audio.mp3", 
  model: "latest_long", 
  format: OmniAI::Transcribe::Format::VERBOSE_JSON
)

# Access the full transcript
result.text # "Complete transcribed text..."

# Access detailed segment information
result.segments.each do |segment|
  puts "Segment #{segment[:segment_id]}: #{segment[:text]}"
  puts "Language: #{segment[:language_code]}"
  puts "Confidence: #{segment[:confidence]}"
  puts "End time: #{segment[:end_time]}"
  
  # Word-level timing (if available)
  segment[:words].each do |word|
    puts "  #{word[:word]} (#{word[:start_time]} - #{word[:end_time]})"
  end
end

# Total audio duration
puts "Total duration: #{result.total_duration}"
```

#### Models

The transcription supports various models optimized for different use cases:

```ruby
# For short audio (< 60 seconds)
client.transcribe("short_audio.mp3", model: OmniAI::Google::Transcribe::Model::LATEST_SHORT)

# For long-form audio (> 60 seconds) - automatically uses async processing
client.transcribe("long_audio.mp3", model: OmniAI::Google::Transcribe::Model::LATEST_LONG)

# For phone/telephony audio
client.transcribe("phone_call.mp3", model: OmniAI::Google::Transcribe::Model::TELEPHONY_LONG)

# For medical conversations
client.transcribe("medical_interview.mp3", model: OmniAI::Google::Transcribe::Model::MEDICAL_CONVERSATION)

# Other available models
client.transcribe("audio.mp3", model: OmniAI::Google::Transcribe::Model::CHIRP_2) # Enhanced model
client.transcribe("audio.mp3", model: OmniAI::Google::Transcribe::Model::CHIRP)   # Universal model
```

**Available Model Constants:**
- `OmniAI::Google::Transcribe::Model::LATEST_SHORT` - Optimized for audio < 60 seconds
- `OmniAI::Google::Transcribe::Model::LATEST_LONG` - Optimized for long-form audio
- `OmniAI::Google::Transcribe::Model::TELEPHONY_SHORT` - For short phone calls
- `OmniAI::Google::Transcribe::Model::TELEPHONY_LONG` - For long phone calls  
- `OmniAI::Google::Transcribe::Model::MEDICAL_CONVERSATION` - For medical conversations
- `OmniAI::Google::Transcribe::Model::MEDICAL_DICTATION` - For medical dictation
- `OmniAI::Google::Transcribe::Model::CHIRP_2` - Enhanced universal model
- `OmniAI::Google::Transcribe::Model::CHIRP` - Universal model

#### Supported Formats

- **Input**: MP3, WAV, FLAC, and other common audio formats
- **GCS URIs**: Direct transcription from Google Cloud Storage
- **File uploads**: Automatic upload to GCS for files > 10MB or long-form models

#### Advanced Features

**Automatic Processing Selection:**
- Files < 60 seconds: Uses synchronous recognition
- Files > 60 seconds or long-form models: Uses asynchronous batch recognition
- Large files: Automatically uploaded to Google Cloud Storage

**GCS Integration:**
- Automatic file upload and cleanup
- Support for existing GCS URIs
- Configurable bucket names

**Error Handling:**
- Automatic retry logic for temporary failures
- Clear error messages for common issues
- Graceful handling of network timeouts

[Google Speech-to-Text API Reference](https://cloud.google.com/speech-to-text/docs)

#### GCS Setup for Transcription

For transcription to work properly with automatic file uploads, you need to set up Google Cloud Storage and configure the appropriate permissions.

##### 1. Create a GCS Bucket

You must create a bucket named `{project_id}-speech-audio` manually before using transcription features:

```bash
# Using gcloud CLI
gsutil mb gs://your-project-id-speech-audio

# Or create via Google Cloud Console
# Navigate to Cloud Storage > Browser > Create Bucket
```

##### 2. Service Account Permissions

Your service account needs the following IAM roles for transcription to work:

**Required Roles:**
- **Cloud Speech Editor** - Grants access to edit resources in Speech-to-Text
- **Storage Bucket Viewer** - Grants permission to view buckets and their metadata, excluding IAM policies
- **Storage Object Admin** - Grants full control over objects, including listing, creating, viewing, and deleting objects

**To assign roles via gcloud CLI:**

```bash
# Replace YOUR_SERVICE_ACCOUNT_EMAIL and YOUR_PROJECT_ID with actual values
SERVICE_ACCOUNT="your-service-account@your-project-id.iam.gserviceaccount.com"
PROJECT_ID="your-project-id"

# Grant Speech-to-Text permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/speech.editor"

# Grant Storage permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/storage.objectAdmin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/storage.legacyBucketReader"
```

**Or via Google Cloud Console:**
1. Go to IAM & Admin > IAM
2. Find your service account
3. Click "Edit Principal" 
4. Add the required roles listed above

##### 3. Enable Required APIs

Ensure the following APIs are enabled in your Google Cloud Project:

```bash
# Enable Speech-to-Text API
gcloud services enable speech.googleapis.com

# Enable Cloud Storage API  
gcloud services enable storage.googleapis.com
```

##### 4. Bucket Configuration (Optional)

You can customize the bucket name by configuring it in your application:

```ruby
# Custom bucket name in your transcription calls
# The bucket must exist and your service account must have access
client.transcribe("audio.mp3", bucket_name: "my-custom-audio-bucket")
```

**Important Notes:**
- The default bucket name follows the pattern: `{project_id}-speech-audio`
- You must create the bucket manually before using transcription features
- Choose an appropriate region for your bucket based on your location and compliance requirements
- Audio files are automatically deleted after successful transcription
- If transcription fails, temporary files may remain and should be cleaned up manually

### Embed

Text can be converted into a vector embedding for similarity comparison usage via:

```ruby
response = client.embed('The quick brown fox jumps over a lazy dog.')
response.embedding # [0.0, ...]
```
