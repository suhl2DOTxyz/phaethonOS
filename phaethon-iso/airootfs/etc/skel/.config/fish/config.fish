# ==============================================================================
# PHAETHON OS - FISH SHELL USER CONFIGURATION
# ==============================================================================
# Shipped at: /etc/skel/.config/fish/config.fish
# Custom Fish configuration providing a high-performance shell environment.
# Sets a themed prompt with a diagonal slash motif and auto-greets with
# fastfetch (running Kitty graphics or Braille ASCII fallback).
#

# Disable greeting message
set fish_greeting

# --- TYPOGRAPHIC COLOR SCHEME (ZZZ UI spec) ---
set -g fish_color_normal normal
set -g fish_color_command C8FF00 --bold  # Lime-yellow commands
set -g fish_color_quote FFFFFF           # White strings
set -g fish_color_redirection 888888
set -g fish_color_end 888888
set -g fish_color_error FF4444           # Red error codes
set -g fish_color_param FFFFFF
set -g fish_color_selection --background=C8FF00 --reverse
set -g fish_color_search_match --background=C8FF00
set -g fish_color_operator C8FF00
set -g fish_color_escape C8FF00
set -g fish_color_autosuggestion 555555

# --- SYSTEM WIDE CUSTOM PROMPT ---
function fish_prompt
    set -l color_accent (set_color C8FF00) # Neon Lime-yellow
    set -l color_white (set_color FFFFFF)  # Pure White
    set -l color_gold (set_color D4AF37)   # Logo Gold
    set -l color_reset (set_color normal)

    # Output structure: [USER@HOSTNAME] // [CWD] >
    echo -n -s $color_white "[" $color_gold $USER "@" (prompt_hostname) $color_white "] "
    echo -n -s $color_accent "// "
    echo -n -s $color_white "[" (prompt_pwd) "] "
    echo -n -s $color_accent "> " $color_reset
end

# --- CUSTOM PATHS & SYSTEM ALIASES ---
alias ls='ls --color=auto'
alias la='ls -A --color=auto'
alias ll='ls -lh --color=auto'
alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias yay-install='yay -S --noconfirm'

# --- INTERACTIVE INITIALIZATION & TERMINAL COMPATIBILITY ---
if status is-interactive
    fastfetch
end
