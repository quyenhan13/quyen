ARCHS := arm64
PACKAGE_FORMAT := ipa
TARGET := iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = TransifyrFrontBoard

TransifyrFrontBoard_FILES = \
  AppDelegate.m \
  AppSceneViewController.m \
  DecoratedAppSceneView.m \
  DecoratedFloatingView.m \
  Hooks.m \
  LauncherViewController.m \
  PiPManager.m \
  ResizeHandleView.m \
  SceneDelegate.m \
  TransifyrSubtitleStore.m \
  TransifyrSubtitleView.m \
  ViewController.m \
  main.m
TransifyrFrontBoard_FRAMEWORKS = UIKit
TransifyrFrontBoard_PRIVATE_FRAMEWORKS = CoreServices FrontBoard RunningBoardServices
TransifyrFrontBoard_CFLAGS = -fcommon -fobjc-arc -Iinclude -I. -Wno-error
# TransifyrFrontBoard_LDFLAGS =
TransifyrFrontBoard_CODESIGN_FLAGS = -Sentitlements.xml

include $(THEOS_MAKE_PATH)/application.mk
