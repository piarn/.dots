# choosenim doesn't read ~/.config/nimble/nimble.ini, so tell it where the
# nim/nimble proxies go (~/.langs/nimble/bin) or it recreates ~/.nimble.
function choosenim --wraps choosenim
    command choosenim --nimbleDir:$HOME/.langs/nimble $argv
end
