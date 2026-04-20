# App-specific R8 rules.
#
# Flutter/plugin keep rules are mostly contributed by the engine and plugin
# consumer rules. Keep the Android entry activity explicit so release minification
# cannot over-trim our method channel surface.
-keep class com.example.lin_player.MainActivity { *; }
