{ config, pkgs, ... }:

let
  # Change this in one place if you want a different git editor.
  gitEditor = "${pkgs.vim}/bin/vim";
  gitIgnoreFile = "${config.home.homeDirectory}/.config/git/ignore";
  gitCommitTemplate = "${config.home.homeDirectory}/.config/git/commit-template";
in
{
  home.file.".config/git/ignore".text = ''
    # Global git ignore patterns
  '';

  home.file.".config/git/commit-template".text = ''
    # <type>: <subject>
    #
    # <body>
    #
    # <footer>
  '';

  programs.git = {
    userName = "Geoffrey Thomas";
    userEmail = "geoff.coppertop@gmail.com";
    extraConfig = {
      alias = {
        pg = "push origin HEAD";
        pgu = "!git push --set-upstream origin \"$(git branch --show-current)\"";
        pgs = "push --force-with-lease";
        up = "pull --rebase";
        pgt = "push --follow-tags";
        prc = "!gh pr create --fill";
        prv = "!gh pr view --web";
        prs = "!gh pr status";
        prm = "!gh pr merge --squash";
        st = "status";
        dft = "difftool";
        met = "mergetool";
        upd = "submodule update --recursive --init";
        lnc = "log --pretty=format:\"%h %s\" --graph --decorate";
        amd = "commit --amend";
        doze = "!git reset --hard && git clean -xffd";
        wash = "!git clean -xffd && git submodule foreach --recursive 'git clean -xffd'";
        nuke = "!git doze && git submodule foreach --recursive 'git doze'";
        terra = "!git nuke && git upd";
      };
      color = {
        diff = "auto";
        status = "auto";
        branch = "auto";
        ui = true;
      };
      commit.template = gitCommitTemplate;
      core = {
        editor = gitEditor;
        excludesfile = gitIgnoreFile;
      };
      diff = {
        guitool = "vscode";
        tool = "vscode";
      };
      difftool = {
        prompt = false;
        vscode.cmd = "code --wait --diff $LOCAL $REMOTE";
      };
      fetch = {
        parallel = 16;
        prune = true;
        recurseSubmodules = false;
      };
      log.follow = true;
      merge = {
        tool = "vscode";
        ff = false;
      };
      mergetool.vscode = {
        cmd = "code --wait $MERGED";
        keepbackup = false;
        trustexitcode = true;
      };
      pull.rebase = true;
      rebase.autoSquash = true;
      status.submoduleSummary = true;
      submodule.fetchJobs = 16;
    };
  };
}