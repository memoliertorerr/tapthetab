# Homebrew cask for TapTheTab, kept in this repository.
#   brew tap memoliertorerr/tapthetab https://github.com/memoliertorerr/tapthetab
#   brew install --cask tapthetab
# Bump with scripts/update-cask.sh after each release.
cask "tapthetab" do
  version "0.10.1"
  sha256 "468b65c48d7f4fd245f0b0664ef92642d3a4eb10e70e6e66a2b17c8d5fde447b"

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
