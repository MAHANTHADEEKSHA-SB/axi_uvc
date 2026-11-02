"""Elaborate SystemVerilog sources with slang (pyslang) and report diagnostics.

Usage: python3 -I slang_elab.py <slang command-line arguments...>

Prints slang's diagnostics, then one summary line with the numbers slang
reports after applying its warning options (suppressed diagnostics are not
counted):
    SLANG_RESULT: errors=<n> warnings=<n> slang=<version>
Exit status 0 when elaboration produced no errors, 1 otherwise.
"""
import sys

import pyslang


def main(argv):
    driver = pyslang.driver.Driver()
    driver.addStandardArgs()
    if not driver.parseCommandLine("slang " + " ".join(argv),
                                   pyslang.driver.CommandLineOptions()):
        return 1
    if not (driver.processOptions() and driver.parseAllSources()):
        return 1
    compilation = driver.createCompilation()
    driver.reportCompilation(compilation, False)
    errors = driver.diagEngine.numErrors
    warnings = driver.diagEngine.numWarnings
    v = pyslang.VersionInfo
    print(f"SLANG_RESULT: errors={errors} warnings={warnings} "
          f"slang={v.getMajor()}.{v.getMinor()}.{v.getPatch()}+{v.getHash()}")
    return 0 if errors == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
