# Homebrew cask for TapTheTab, kept in this repository.
#   brew tap memoliertorerr/tapthetab https://github.com/memoliertorerr/tapthetab
#   brew install --cask tapthetab
# Bump with scripts/update-cask.sh after each release.
cask "tapthetab" do
  version "0.4.0"
  sha256 "20ca10f13c5d794970442c23573287547a093b12bbae2b5c97438ed50d44a95f"

  url "https://github.com/memoliertorerr/tapthetab/releases/download/v#{version}/TapTheTab-#{version}.dmg"
  name "TapTheTab"
  desc "Keyboard-first window switcher with type-to-search"
  homepage "https://github.com/memoliertorerr/tapthetab"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "TapTheTab.app"

  uninstall quit: "io.github.memoliertorerr.TapTheTab"

  zap trash: "~/Library/Application Support/TapTheTab"
end
