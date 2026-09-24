# App-specific R8 rules for the release build.
#
# The Flutter Gradle plugin contributes the rules the engine and the plugins
# need, so this file is deliberately almost empty: every rule here is one that
# R8 cannot work out for itself, and each needs a reason beside it.
#
# The three plugins with a native side — flutter_secure_storage, local_auth
# and flutter_local_notifications — are reached through method channels rather
# than reflection, so their classes are held by the generated plugin
# registrant and need no keep rule.

# R8 warns about annotations Google's crypto libraries reference but do not
# ship; they are compile-time only and their absence is not a problem.
-dontwarn javax.annotation.**
