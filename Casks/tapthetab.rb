# Homebrew cask for TapTheTab, kept in this repository.
#   brew tap memoliertorerr/tapthetab https://github.com/memoliertorerr/tapthetab
#   brew install --cask tapthetab
# Bump with scripts/update-cask.sh after each release.
cask "tapthetab" do
  version "0.3.0"
  sha256 "b7caaeb33f9deb293a8e160fe15f9ec70ac324a5ace9762a6f211c7a7bee0207"

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
