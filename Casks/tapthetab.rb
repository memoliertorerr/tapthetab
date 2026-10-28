# Homebrew cask for TapTheTab, kept in this repository.
#   brew tap memoliertorerr/tapthetab https://github.com/memoliertorerr/tapthetab
#   brew install --cask tapthetab
# Bump with scripts/update-cask.sh after each release.
cask "tapthetab" do
  version "0.2.0"
  sha256 "2630f290c3480bf7806c7f639d6645333861cf1bd2af82a26681e548d3e8ff02"

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
