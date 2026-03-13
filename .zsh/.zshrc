# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/Projects/popcorn/popcorn-m/.zsh/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

source /nix/store/gnwfrf0rn9xx5h5gj1sbhlm8w76iqv2n-powerlevel10k-1.20.15/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
eval "$(zoxide init zsh)"
alias ls="eza --icons"
setopt interactive_comments

# To customize prompt, run `p10k configure` or edit ~/Projects/popcorn/popcorn-m/.zsh/.p10k.zsh.
[[ ! -f ~/Projects/popcorn/popcorn-m/.zsh/.p10k.zsh ]] || source ~/Projects/popcorn/popcorn-m/.zsh/.p10k.zsh
