# Arkham Proxy

```
eval "$(rbenv init - zsh)" && cd /Users/ahmedelbannan/Ahmed/ahiskali-arkham-print && rails server
```
(The app runs on port 3001 by default; open http://localhost:3001)

This is a web app to generate printable PDF proxies for Arkham Horror: The Card Game cards from [ArkhamDB](https://arkhamdb.com/).

~~It's live at [https://arkham-proxy.herokuapp.com/](https://arkham-proxy.herokuapp.com/)~~

It's not live since Heroku discontinued their free dynos, I'm looking into another hosting.

## Features

- **Multiple Input Methods**: Generate PDFs from deck IDs, individual card IDs, or pack codes
- **Double-Sided Printing**: Automatically generates front and back pages for easy double-sided printing
- **Smart Card Backs**: 
  - Double-sided cards use their specific back images
  - Single-sided cards get appropriate generic backs (Mythos or Player)
- **Professional Layout**:
  - Standard card size (63mm x 88mm)
  - 2mm black borders with rounded corners
  - 3 cards per row in a centered layout
  - Horizontal reversal for backs to align when printed double-sided
- **Image Processing**:
  - AVIF format support with automatic conversion
  - Auto-rotation for landscape images
  - Width cropping for single-sided cards (827px)
- **Batch Processing**: Efficiently processes multiple packs at once

## Prerequisites

Before running this project, make sure you have the following installed:

- **Ruby** (version 2.3 or higher)
  - Check: `ruby --version`
  - Install: [https://www.ruby-lang.org/en/downloads/](https://www.ruby-lang.org/en/downloads/)
  
- **Bundler**
  - Check: `bundle --version`
  - Install: `gem install bundler`
  
- **ImageMagick** (required for image processing with MiniMagick)
  - Check: `magick --version` or `convert --version`
  - Install:
    - macOS: `brew install imagemagick`
    - Linux: `sudo apt-get install imagemagick`
    - Windows: Download from [https://imagemagick.org/](https://imagemagick.org/)

## Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/fahseltc/ahiskali-arkham-print.git
   cd ahiskali-arkham-print
   ```

2. **Install dependencies**
   ```bash
   bundle install
   ```

That's it! This application doesn't use a database, so no additional setup is needed.

## Running the Project

### Development Server

Start the Rails development server:

```bash
rails server
```

Or use the shorthand:

```bash
rails s
```

You can also explicitly specify the environment:

```bash
rails server -e development
```

Or combine with a custom port:

```bash
rails server -e development -p 3001
```

The application will be available at [http://localhost:3001](http://localhost:3001)

### Troubleshooting

If you encounter any issues:

1. **Missing ImageMagick**: Make sure ImageMagick is installed
   ```bash
   # macOS
   brew install imagemagick
   
   # Linux
   sudo apt-get install imagemagick
   ```

2. **Bundle install fails**: Make sure you have the correct Ruby version
   ```bash
   ruby --version  # Should be 2.3 or higher
   ```

3. **Port already in use**: Use a different port
   ```bash
   rails server -p 3001
   ```

### Using a Different Port

To run on a different port (e.g., 3001):

```bash
rails server -p 3001
```

## Usage

Once the server is running, visit [http://localhost:3001](http://localhost:3001) and you'll see three options:

### Option 1: From ArkhamDB Deck
- Enter a deck ID or paste a full ArkhamDB deck URL
- Example: `12345` or `https://arkhamdb.com/decklist/view/12345`

### Option 2: From Card IDs
- Enter comma-separated card IDs
- Example: `01001, 01002, 01003`
- Cards with the same ID will be included multiple times

### Option 3: From Pack Code(s)
- Enter one or more pack codes (comma-separated)
- Examples:
  - Single pack: `core`
  - Multiple packs: `core, dwl, ptc`
  - Full campaign: `dwl, tmm, tuo, wda, uau, litas, bota, litas`

The application will generate a PDF with:
- Every 9 cards: one page of fronts, one page of backs
- Backs reversed horizontally for proper alignment when printed double-sided
- 2mm black borders with rounded corners on each card

## Built With

- [Ruby on Rails](https://rubyonrails.org/) - Web framework
- [Prawn](https://github.com/prawnpdf/prawn) - PDF generation
- [MiniMagick](https://github.com/minimagick/minimagick) - Image processing
- [HTTParty](https://github.com/jnunemaker/httparty) - API calls to ArkhamDB

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details
