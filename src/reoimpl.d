import std.stdio;
import std.typecons; // Nullable
import std.c.stdlib; // exit()
import std.path;
import std.process;
import std.getopt;
import std.file;
import std.format;
import std.string;

import config;
import dirconfig;
import dini;
import log;
import builder;
import impl;

struct RebarBuildOptions {
  string repo;
  string tag;
  string id;
  string configname;
}

// executables to symlink to after a build is complete

string[] bins = [
  "rebar"
];


class ReoImpl : Impl {
    string reosectionname; // [Reo] or [Reo3] in the reo_config file

    this() {
      IdKey = "Rebars";
      name = "reo";
      commands = ["rebar"];
      installbasedir = getConfigSubdir("rebars");
      repodir = getConfigSubdir("rebar_repos");
      appConfigName = "reo_config";
      reosectionname = "Reo";
    }

    override string[] getBins() {
      return bins;
    }

    override void initOnce() {
      log_debug("reo init once");

      if(exists(buildNormalizedPath(getConfigDir(), appConfigName))) {
        log_debug("reo has already been initialized");
        return;
      }

      mkdirSafe(getConfigDir());
      mkdirSafe(buildNormalizedPath(getConfigDir(), "rebars"));
      mkdirSafe(buildNormalizedPath(getConfigDir(), "rebar_repos"));
      // create ~/.erln8.d
      // create ~/.erln8.d/otps/
      // create ~/.erln8.d/repos/

      // create ~/.erln8.d/config file
      File config = File(buildNormalizedPath(getConfigDir(), "reo_config"), "w");
      // "none" must be left in, otherwise the section will be empty
      config.writeln(q"EOS
[Reo]
default_config=default
system_default=
color=true

[Repos]
default=https://github.com/rebar/rebar.git

[Rebars]
none =

[Configs]
EOS"
);
      config.close();

      setupBins();

      //Ini cfg = getAppConfig();
      //doClone(cfg, "default");
    }

    override void processArgs(string[] args, bool showHelp) {
      CommandLineOptions opts;
      try {
        auto rslt = getopt(
            args,
            std.getopt.config.passThrough,
            "use",       "Setup the current directory to use a specific verion of Rebar", &opts.opt_use,
            "list",      "List installed versions of Rebar",      &opts.opt_list,
            "remote",    "add/delete/show remotes", &opts.opt_remote,
            "clone",     "Clone a Rebar source repository",  &opts.opt_clone,
            "fetch",     "Update source repos",  &opts.opt_fetch,
            "build",     "Build a specific version of Rebar from source",  &opts.opt_build,
            "build-latest", "Build the latest tagged version of Rebar from source",  &opts.opt_build_latest,
            "repo",      "Specifies repo name to build from",  &opts.opt_repo,
            //"tag",       "Specifies repo branch/tag to build fro,",  &opts.opt_tag,
            "id",        "A user assigned name for a version of Rebar",  &opts.opt_id,
            "config",    "Build configuration",  &opts.opt_config,
            "show",      "Show the configured version of Rebar in the current working directory",  &opts.opt_show,
            "prompt",    "Same as above without a newline, suitable to use in a prompt",  &opts.opt_prompt,
            "configs",   "List build configs",  &opts.opt_configs,
            "repos",     "List build repos",  &opts.opt_repos,
            "force",     "Overwrite an erln8.config in the current directory",  &opts.opt_force,
            "buildable", "List tags to build from configured source repos", &opts.opt_buildable,
            "version",   "Show the installed version of reo", &opts.opt_version,
            "setup-bins",    "Regenerate erln8-managed OTP application links", &opts.opt_setup_bins,
            "debug",     "Show debug output", &opts.opt_debug
              );
        if(showHelp && rslt.helpWanted) {
          // it's an Arrested Development joke
          auto bannerMichael = "Usage: " ~ name ~ " [--use <id> --force] [--list] [--remote add|delete|show]\n";
          bannerMichael ~= "       [--clone <remotename>] [--fetch <remotename>] [--show] [--prompt]\n";
          bannerMichael ~= "       [--build --id <someid> --repo <remotename> --config <configname>]\n";
          bannerMichael ~= "       [--buildable] [--configs] \n";
          defaultGetoptPrinter(bannerMichael.color(fg.yellow), rslt.options);
          exit(0);
        }
        log_debug(opts);
        opts.allargs = args;
        currentOpts = opts;
      } catch (Exception e) {
        writeln(e.msg);
        exit(-1);
      }
    }



    override string[] getSymlinkedExecutables() {
      string[] all = [];
      foreach(bin;bins) {
        all = all ~ baseName(bin);
      }
      return all;
    }

    void doShow(Ini cfg) {
      DirconfigResult dcr = getConfigFromCWD("Rebar");
      auto dirini = dcr.ini;
      if(dirini.isNull) {
        log_fatal("Can't find a configured version of Rebar");
        exit(-1);
      }

      log_debug("Rebar id:", dirini["Config"].getKey("Rebar"));
      string rebarid = dirini["Config"].getKey("Rebar");
      if(!isValidRebar(cfg, rebarid)) {
        log_fatal("Unknown Rebar id: ", rebarid);
        exit(-1);
      }
      if(currentOpts.opt_show) {
        auto path = cfg["Rebars"].getKey(rebarid);
        writeln(rebarid, " @ ", path);
      } else {
        write(rebarid);
      }
    }

    void doUse(Ini cfg) {
      auto keys = cfg[IdKey].keys();
      log_debug("Trying to use ", currentOpts.opt_use);
      string rebarId = currentOpts.opt_use;
      if(!(rebarId in keys)) {
        writeln(rebarId, " is not a configured version of Rebar");
        exit(-1);
      }
      string fileName = "erln8.config";
      if(exists(fileName)) {
        if(!currentOpts.opt_force) {
          writeln("Config already exists in this directory. Override with --force.");
          exit(-1);
        }
      }

      if(currentOpts.opt_force) {
        // update the existing file
        DirconfigResult dcr = getConfigFromCWD();
        auto dircfg = dcr.ini;
        IniSection inicfg = dircfg.get().getSection("Config");
        inicfg.setKey("Rebar", rebarId);
        saveDirConfig(dcr.path, dcr.ini);
      } else {
        // write a new file
        File file = File("erln8.config", "w");
        file.writeln("[Config]");
        file.writeln("Rebar=", rebarId);
      }

    }


    bool isValidRebar(Ini ini, string id) {
      return ini[IdKey].hasKey(id);
    }

    RebarBuildOptions getBuildOptions(string repo, string tag, string id, string configname) {
      RebarBuildOptions opts;
      opts.repo = (repo == null ? "default" : repo);
      opts.tag = tag;

      if(opts.id == null) {
        opts.id  = tag;
      } else {
        opts.id  = id;
      }

      // TODO: use Rebar.default_config value here
      //opts.configname = (configname == null ? "default_config" : configname);
      opts.configname = configname;
      return opts;
    }

    void verifyInputs(Ini cfg, RebarBuildOptions build_options) {
      auto rebars = cfg[IdKey].keys();
      if(build_options.id in rebars) {
        writeln("A version of Rebar already exists with the id ", build_options.id);
        exit(-1);
      }

      auto repos = cfg["Repos"].keys();
      if(!(build_options.repo in repos)) {
        writeln("Unconfigured repo: ", build_options.repo);
        exit(-1);
      }

      string repoURL = cfg["Repos"].getKey(build_options.repo);
      string repoPath = buildNormalizedPath(getConfigSubdir(repodir),build_options.repo);

      if(!exists(repoPath)) {
        writeln("Missing repo for " ~ currentOpts.opt_fetch
            ~ ", which should be in " ~ repoPath ~ ". Maybe you forgot to reo --clone <repo_name>");
        exit(-1);
      }

      // TODO
      //auto configs = cfg["Configs"].keys();
      //if(!(build_options.configname in configs)) {
      //  writeln("Unknown build config: ", build_options.configname);
      //  exit(-1);
      // }

    }

    void checkObject(RebarBuildOptions opts, string sourcePath) {
      string checkObj = "cd " ~ sourcePath ~ " && git show-ref " ~ opts.tag ~ " > /dev/null";
      log_debug(checkObj);
      auto shell = executeShell(checkObj);
      if(shell.status != 0) {
        writeln("branch or tag " ~ opts.tag ~ " does not exist in " ~ opts.repo ~ " Git repo");
        log_debug("Git object missing");
        exit(-1);
      } else {
        log_debug("Git object exists");
      }
    }


    // TODO: NEEDS A SYSTEM DEFAULT IF ONE ISN'T SET
    override void doBuild(Ini cfg, string tag) {
      RebarBuildOptions opts = getBuildOptions(currentOpts.opt_repo,
          tag,
          currentOpts.opt_id,
          currentOpts.opt_config);

      verifyInputs(cfg, opts);

      string outputRoot = buildNormalizedPath(getConfigSubdir(installbasedir),opts.id);
      string outputPath = buildNormalizedPath(outputRoot);
      string sourcePath = buildNormalizedPath(getConfigSubdir(repodir), opts.repo);

      checkObject(opts, sourcePath);
      string makeBin = getMakeBin();

      // TODO: build config _env
      string env = "";

      log_debug("Output root = ", outputRoot);
      log_debug("Output path = ", outputPath);
      log_debug("Source path = ", sourcePath);

      string tmp = buildNormalizedPath(tempDir(), getTimestampedFilename());
      log_debug("tmp dir = ", tmp);
      string logFile = buildNormalizedPath(tmp, "build_log");
      log_debug("log = ", tmp);

      mkdirRecurse(tmp);
      mkdirRecurse(outputPath);
      string cmd0 = format("%s cd %s && git archive %s | (cd %s; tar -f - -x)",
          env,  sourcePath,     opts.tag, tmp);

      string cmd1 = format("%s cd %s && ./bootstrap > ./build_log 2>&1",
          env, tmp);

      string cmd2 = format("%s cd %s && cp ./rebar %s/rebar > ./build_log 2>&1",
          env, tmp, outputPath);

      Builder b = new Builder();
      b.addCommand("Copy source          ", cmd0);
      b.addCommand("Bootstrap            ", cmd1);
      b.addCommand("Install              ", cmd2);

      if(!b.run()) {
        writeln("*** Build failed ***");
        writeln("Here are the last 10 lines of " ~ logFile);
        auto pid = spawnShell("tail -10 " ~ logFile);
        wait(pid);
        return;
      }
      log_debug("Adding Rebar id to ~/.erln8/reo_config");
      cfg[IdKey].setKey(opts.id, outputPath);
      saveAppConfig(cfg);
      setSystemDefaultIfFirst("Reo", opts.id);
      writeln("Done!");
    }

    override void runConfig() {
      Ini cfg = getAppConfig();
      if(currentOpts.opt_buildable) {
        doBuildable(cfg);
      } else if(currentOpts.opt_list) {
        doList(cfg);
      } else if(currentOpts.opt_repos) {
        doRepos(cfg);
      } else if(currentOpts.opt_show || currentOpts.opt_prompt) {
        doShow(cfg);
      } else if(currentOpts.opt_configs) {
        doConfigs(cfg);
      } else if(currentOpts.opt_use) {
        doUse(cfg);
      } else if(currentOpts.opt_clone) {
        doClone(cfg);
      } else if(currentOpts.opt_fetch) {
        doFetch(cfg);
      } else if(currentOpts.opt_build) {
        foreach(b;currentOpts.opt_build) {
          doBuild(cfg, b);
        }
      } else if(currentOpts.opt_build_latest) {
        doBuildLatest(cfg);
      } else if(currentOpts.opt_version) {
        writeln(name, " ", erln8_version); 
      } else if(currentOpts.opt_setup_bins) {
        doSetupBins(cfg); 
      } else {
        log_debug("Nothing to do");
      }
    }

    override void runCommand(string[] cmdline) {
      Ini cfg = getAppConfig();
      log_debug("Config:", cfg);
      log_debug("Running: ", cmdline);
      string bin = baseName(cmdline[0]);

      DirconfigResult dcr = getConfigFromCWD("Rebar");
      log_debug("Got config from cwd");
      auto dirini = dcr.ini;
      string rebarId;

      if(dirini.isNull) {
        IniSection e8cfg = cfg.getSection(reosectionname);
        if(e8cfg.hasKey("system_default") && e8cfg.getKey("system_default") != null ) {
          log_debug("Using system_default ", e8cfg.getKey("system_default"));
          rebarId = e8cfg.getKey("system_default");
        } else {
          log_fatal("Can't find a configured version of Rebar");
          exit(-1);
        }
      } else {
         if(dirini["Config"].hasKey("Rebar")) {
           rebarId = dirini["Config"].getKey("Rebar");
           log_debug("Rebar id:", dirini["Config"].getKey("Rebar"));
         } else {
           writeln("Rebar version not specified"); 
         }
      }

      if(!isValidRebar(cfg, rebarId)) {
        log_fatal("Unknown Rebar id: ", rebarId);
        exit(-1);
      }
      log_debug("installbasedir = ", installbasedir);
      log_debug("repodir = ", repodir);

      string binFullPath = buildNormalizedPath(installbasedir, rebarId, bin);
      log_debug("mapped cmd to execute = ", binFullPath);
      auto argsPassthrough = [bin] ~ cmdline[1 .. $];
      log_debug("Args = ", argsPassthrough);
      execv(binFullPath, argsPassthrough);
    }

}



