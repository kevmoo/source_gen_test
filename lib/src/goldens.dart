import 'dart:io';

const updateGoldensVariable = 'SOURCE_GEN_TEST_UPDATE_GOLDENS';

bool get updateGoldens => Platform.environment[updateGoldensVariable] == '1';
