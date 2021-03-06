import std.path;
import std.file;
import std.stdio;
import std.regex;
import std.c.stdlib; // exit()
import std.process;
import std.format;
import std.string;
import std.getopt;
import std.datetime;
import colorize : fg, color, cwrite, cwriteln;

import config;
import dini;
import log;

enum RemoteOption { none, add, remove, show };

struct CommandLineOptions {
  string       opt_use           = null;
  bool         opt_list          = false;
  string       opt_clone         = null;
  string       opt_fetch         = null;
  string[]     opt_build         = null;
  bool         opt_build_latest  = false;
  string       opt_with_erlang  = null;
  string       opt_repo          = null;
  string       opt_id            = null;
  string       opt_config        = null;
  bool         opt_show          = false;
  bool         opt_prompt        = false;
  bool         opt_configs       = false;
  bool         opt_repos         = false;
  bool         opt_force         = false;
  bool         opt_buildable     = false;
  bool         opt_debug         = false;
  bool         opt_env           = false;
  string       opt_set_default   = null;
  bool         opt_get_default   = false;
  bool         opt_version       = false;
  bool         opt_setup_bins    = false;
  RemoteOption opt_remote        = RemoteOption.none;
  string[] allargs;
}

class Impl {
  CommandLineOptions currentOpts;
  string name;
  string[] commands;

  string IdKey;           // cfg["Erlangs"], cfg["Rebars"] etc
  string installbasedir;  // where the compiled packages live
  string repodir;         // where erln8/reo keeps this impls git repo
  string appConfigName;   // ~/.erln8.d/foo_config

  abstract void initOnce();
  abstract void runCommand(string[] cmdline);
  abstract void runConfig();
  abstract string[] getSymlinkedExecutables();
  abstract void processArgs(string[] args, bool showHelp);
  abstract string[] getBins();

  void doBuild(Ini cfg, string tag) {}

  void setupBins() {
    auto binPath = buildNormalizedPath(getConfigDir(), "bin");
    string msg = ("PLEASE ADD " ~ binPath ~ " TO YOUR PATH").color(fg.red);
    cwriteln(msg);
    mkdirSafe(binPath);
    foreach(bin;getSymlinkedExecutables()) {
      auto linkTo = buildNormalizedPath(binPath, baseName(bin));
      try {
        //writeln("Creating symlink for ", baseName(linkTo));
        symlink(thisExePath(), linkTo);
      } catch (Exception e) {
        writeln("Could not link: ", e.msg, ". Ok to continue.");
      }
    }
  }


  Ini getAppConfig() {
    string cfgFileName = buildNormalizedPath(getConfigDir(), appConfigName);
    log_debug("Attempting to load ", cfgFileName);
    if(!exists(cfgFileName)) {
      log_fatal(name ~ "has not been initialized");
      exit(-1);
    }
    Ini ini = Ini.Parse(cfgFileName);
    return ini;
  }

  void saveAppConfig(Ini cfg) {
    string cfgFileName = buildNormalizedPath(getConfigDir(), appConfigName);
    log_debug("Attempting to save ", cfgFileName);
    if(!exists(cfgFileName)) {
      log_fatal("erln8 has not been initialized");
      exit(-1);
    }

    File output = File(cfgFileName, "w");
    foreach(section;cfg.sections) {
      auto keys = cfg[section.name].keys();
      output.writeln("[" ~ section.name ~ "]");
      foreach(k,v;keys) {
        output.writeln(k, "=", v);
      }
      output.writeln("");
    }
  }

  void saveDirConfig(string path, Ini cfg) {
    File output = File(path, "w");
    foreach(section;cfg.sections) {
      auto keys = cfg[section.name].keys();
      output.writeln("[" ~ section.name ~ "]");
      foreach(k,v;keys) {
        output.writeln(k, "=", v);
      }
      output.writeln("");
    }
  }


  void init() {
    string firstBin = baseName(getBins()[0]);
    string firstLinked = buildNormalizedPath(getConfigDir(), "bin", firstBin);
    if(exists(firstLinked)) {
      log_debug(name ~ " has already been initialized");
      return;
    } else {
      initOnce();
    }
  }

  void mkdirSafe(string d) {
    try {
      mkdir(d);
    } catch(FileException fe) {
      auto ctr = ctRegex!(`File exists`);
      auto c2 = matchFirst(fe.msg, ctr);
      if(c2.empty) {
        writeln(fe.msg);
        throw fe;
      } else {
        log_debug("File already exists: ", d);
      }
    }
  }

  string getConfigSubdir(string subdir) {
    return expandTilde(buildNormalizedPath(getConfigDir(), subdir));
  }

  void doBuildable(Ini cfg) {
    auto keys = cfg["Repos"].keys();
    log_debug(keys);
    foreach(k,v;keys) {
      log_debug("Listing buildable in repo ", k, " @ ", v);
      writeln("Tags in repo ", k, ":");
      string currentRepoDir = buildNormalizedPath(repodir, k);
      log_debug(currentRepoDir);
      string cmd = "cd " ~ currentRepoDir ~ " && git tag | sort | pr -3 -t";
      log_debug(cmd);
      auto pid = spawnShell(cmd);
      wait(pid);
    }
  }


  void doBuildLatest(Ini cfg) {
    string repo = currentOpts.opt_repo == null ? "default" : currentOpts.opt_repo;
    string sourcePath = buildNormalizedPath(getConfigSubdir(repodir), repo);
    string cmd = "cd " ~ sourcePath ~ " && git describe --tags `git rev-list --tags --max-count=1`";

    auto cmdout = executeShell(cmd);
    string finaltag = cmdout.output.strip;
    writeln("Latest tag = ", finaltag);
    doBuild(cfg, finaltag);
  }

  void doList(Ini cfg) {
    auto keys = cfg[IdKey].keys();
    log_debug(keys);
    foreach(k,v;keys) {
      if(k != "none")
        writeln(k, " -> ", v);
    }
  }

  void doRepos(Ini cfg) {
    auto keys = cfg["Repos"].keys();
    foreach(k,v;keys) {
      writeln(k," -> ", v);
    }
  }

  void doConfigs(Ini cfg) {
    auto keys = cfg["Configs"].keys();
    foreach(k,v;keys) {
      writeln(k," -> ", v);
    }
  }

  void doSetupBins(Ini cfg) {
    setupBins();
  }

  void doClone(Ini cfg) {
    doClone(cfg, currentOpts.opt_clone);
  }

  void doClone(Ini cfg, string name) {
    auto keys = cfg["Repos"].keys();
    if(!(name in keys)) {
      writeln("Unknown repo:", name);
      exit(-1);
    }
    string repoURL = cfg["Repos"].getKey(name);
    string dest = buildNormalizedPath(getConfigSubdir(repodir),name);
    string command = "git clone " ~ repoURL ~ " " ~ dest;
    log_debug(command);
    auto pid = spawnShell(command);
    wait(pid);
  }

  void doFetch(Ini cfg) {
    auto keys = cfg["Repos"].keys();
    if(!(currentOpts.opt_fetch in keys)) {
      writeln("Unknown repo:", currentOpts.opt_fetch);
      exit(-1);
    }
    string repoURL = cfg["Repos"].getKey(currentOpts.opt_fetch);
    string dest = buildNormalizedPath(getConfigSubdir(repodir),currentOpts.opt_fetch);

    if(!exists(dest)) {
      writeln("Missing repo for " ~ currentOpts.opt_fetch
          ~ ", which should be in " ~ dest ~ ". Maybe you forgot to reo --clone <repo_name>");
      exit(-1);
    }
    string command = "cd " ~ dest ~ "  && git fetch --all";
    log_debug(command);
    auto pid = spawnShell(command);
    wait(pid);
  }

  void doRemote(Ini cfg) {
    if(currentOpts.opt_remote == RemoteOption.show) {
      auto keys = cfg["Repos"].keys();
      foreach(k,v;keys) {
        writeln(k, " -> ", v);
      }
      exit(0);
    }

    if(currentOpts.opt_remote == RemoteOption.add ||
        currentOpts.opt_remote == RemoteOption.remove) {
      // processing the args removes them from the array

      if(currentOpts.opt_remote == RemoteOption.add) {
        if(currentOpts.allargs.length != 3) {
          writeln("Invalid arguments specified");
          exit(-1);
        }

        string name = currentOpts.allargs[$-2];
        string url  = currentOpts.allargs[$-1];
        writeln("Adding remote ", name, " -> ", url);
        cfg["Repos"].setKey(name, url);
        saveAppConfig(cfg);
        exit(0);
      } else if(currentOpts.opt_remote == RemoteOption.remove) {
        if(currentOpts.allargs.length != 2) {
          writeln("Invalid arguments specified");
          exit(-1);
        }

        string name = currentOpts.allargs[$-1];
        cfg["Repos"].removeKey(name);
        writeln("Removing remote ", name);
        saveAppConfig(cfg);
        exit(0);
      }


    }

    //string currentRepoDir = buildNormalizedPath(repodir
    //cfg["Erlangs"].setKey(opts.id, outputPath);
    //saveAppConfig(cfg);
  }


  string getTimestampedFilename() {
    auto currentTime = Clock.currTime();
    auto timeString = currentTime.toISOExtString();
    return timeString.replace("-","_").replace(":","_").replace(".", "_");
  }

  void setSystemDefaultIfFirst(string section, string id) {
    Ini cfg = getAppConfig();
    IniSection e8cfg = cfg.getSection(section);
    if(e8cfg.hasKey("system_default") && e8cfg.getKey("system_default") == null ) {
      write("A system default hasn't been set. Would you like to use ", id, " as the system default? (y/N) ");
      string line = readln();
      if(line.toLower().strip() == "y") {
        e8cfg.setKey("system_default", id);
        saveAppConfig(cfg);
      }
    }
  }

  void setSystemDefault(string configSection, string installedSection, string id) {
    Ini cfg = getAppConfig();

    IniSection installed = cfg.getSection(installedSection);
    if(!installed.hasKey(id)) {
      log_fatal("Invalid id specified");
      exit(-1);
    }
    IniSection e8cfg = cfg.getSection(configSection);
    e8cfg.setKey("system_default", id);
    saveAppConfig(cfg);
  }

  void getSystemDefault(string configSection) {
    Ini cfg = getAppConfig();
    IniSection e8cfg = cfg.getSection(configSection);
    writeln(e8cfg.getKey("system_default"));

  }

  void setupLinks(string root) {
      foreach(bin;getBins()) {
        string base = baseName(bin);
        if(bin.indexOf('*') >= 0) {
          // paths that include a *
          string p = buildNormalizedPath(root, "dist", bin);
          log_debug("Getting full path of ", p);
          log_debug("  basename = ", base);
          auto ls = executeShell("ls " ~ p);
          if (ls.status != 0) {
            writeln("Failed to find file while creating symlink: ", p);
            writeln("Most likely an outdated command. Moving on.");
            // keep going, most likely a command that doesn't exist in a
            // newer version of Erlang
          } else {
            if(splitLines(ls.output).length > 1) {
              log_fatal("Found more than 1 executable for ", p , " while creating symlinks");
              exit(-1);
            }
            string fullpath = strip(splitLines(ls.output)[0]);
            string linkTo = buildNormalizedPath(root, base);
            log_debug("Found ", fullpath);
            log_debug("symlink ", fullpath, " to ", linkTo);
            symlink(fullpath, linkTo);
          }
        } else {
          // paths that do not include a *
          string fullpath = buildNormalizedPath(root, "dist", bin);
          string linkTo = buildNormalizedPath(root, base);
          log_debug("symlink ", fullpath, " to ", linkTo);
          symlink(fullpath, linkTo);
        }
      }
    }

}
