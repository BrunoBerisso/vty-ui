{-# LANGUAGE TypeSynonymInstances, FlexibleInstances #-}
module Graphics.Vty.Widgets.CheckBox
    ( CheckBox
    , RadioGroup
    , newCheckbox
    , newRadioGroup
    , addToRadioGroup
    , toggleChecked
    , setCheckboxUnchecked
    , setCheckboxChecked
    , setCheckedChar
    , onCheckboxChange
    , checkboxIsChecked
    )
where

import Data.IORef
    ( IORef
    , newIORef
    , readIORef
    , writeIORef
    )
import Data.Maybe
    ( isJust
    , fromJust
    )
import Control.Monad
    ( when
    )
import Control.Monad.Trans
    ( MonadIO
    , liftIO
    )
import Graphics.Vty
    ( Attr
    , Key(..)
    , Modifier
    , string
    , region_width
    , def_attr
    )
import Graphics.Vty.Widgets.Core
    ( Widget
    , WidgetImpl(..)
    , HasNormalAttr(..)
    , HasFocusAttr(..)
    , RenderContext(..)
    , (<~)
    , (<~~)
    , getState
    , newWidget
    , updateWidget
    , updateWidgetState
    , getPhysicalPosition
    , withWidth
    )
import Graphics.Vty.Widgets.Util

data RadioGroupData = RadioGroupData { currentlySelected :: Maybe (Widget CheckBox)
                                     }

type RadioGroup = IORef RadioGroupData

newRadioGroup :: (MonadIO m) => m RadioGroup
newRadioGroup = liftIO $ newIORef $ RadioGroupData Nothing

setCheckedChar :: (MonadIO m) => Widget CheckBox -> Char -> m ()
setCheckedChar wRef ch =
    updateWidgetState wRef $ \s -> s { checkedChar = ch
                                      }

addToRadioGroup :: (MonadIO m) => RadioGroup -> Widget CheckBox -> m ()
addToRadioGroup rg wRef = do
  updateWidgetState wRef $ \s -> s { radioGroup = Just rg
                                   }
  setCheckedChar wRef '*'

radioGroupSetCurrent :: (MonadIO m) => Widget CheckBox -> m ()
radioGroupSetCurrent wRef = do
  mRg <- radioGroup <~~ wRef

  when (isJust mRg) $
       do
         let Just rg = mRg
         rgData <- liftIO $ readIORef rg

         -- If the radio group has a currently-selected checkbox,
         -- uncheck it (but only if it's a different widget: it could
         -- be the only one in this group!)
         when ((isJust $ currentlySelected rgData) &&
               (currentlySelected rgData /= Just wRef)) $
              setChecked__ (fromJust $ currentlySelected rgData) False

         liftIO $ writeIORef rg $ rgData { currentlySelected = Just wRef }
         setChecked__ wRef True

instance HasNormalAttr (Widget CheckBox) where
    setNormalAttribute wRef a =
        updateWidgetState wRef $ \s -> s { cbNormalAttr = a }

instance HasFocusAttr (Widget CheckBox) where
    setFocusAttribute wRef a =
        updateWidgetState wRef $ \s -> s { cbFocusedAttr = a }

data CheckBox = CheckBox { isChecked :: Bool
                         , cbNormalAttr :: Attr
                         , cbFocusedAttr :: Attr
                         , checkedChar :: Char
                         , checkboxLabel :: String
                         , checkboxChangeHandler :: Widget CheckBox -> Bool -> IO ()
                         , radioGroup :: Maybe RadioGroup
                         }

instance Show CheckBox where
    show cb = concat [ "CheckBox { "
                     , "isChecked = ", show $ isChecked cb
                     , ", cbNormalAttr = ", show $ cbNormalAttr cb
                     , ", cbFocusedAttr = ", show $ cbFocusedAttr cb
                     , ", checkedChar = ", show $ checkedChar cb
                     , ", checkboxLabel = ", show $ checkboxLabel cb
                     , " }"
                     ]

newCheckbox :: (MonadIO m) => String -> m (Widget CheckBox)
newCheckbox label = do
  wRef <- newWidget
  updateWidget wRef $ \w ->
      w { state = CheckBox { isChecked = False
                           , cbNormalAttr = def_attr
                           , cbFocusedAttr = def_attr
                           , checkedChar = 'x'
                           , checkboxLabel = label
                           , checkboxChangeHandler = \_ _ -> return ()
                           , radioGroup = Nothing
                           }
        , cursorInfo =
            \this -> do
              pos <- getPhysicalPosition this
              return $ Just (pos `withWidth` (region_width pos + 1))

        , keyEventHandler = radioKeyEvent
        , draw =
            \this sz ctx -> do
              f <- focused <~ this
              st <- getState this

              let attr = mergeAttrs [ overrideAttr ctx
                                    , cbNormalAttr st
                                    , normalAttr ctx
                                    ]

                  fAttr = if f
                          then mergeAttrs [ cbFocusedAttr st
                                          , focusAttr ctx
                                          ]
                          else attr

                  ch = if isChecked st then checkedChar st else ' '

                  s = ['[', ch, ']', ' '] ++ (checkboxLabel st)

              return $ string fAttr $ take (fromEnum $ region_width sz) s
        }
  return wRef

radioKeyEvent :: Widget CheckBox -> Key -> [Modifier] -> IO Bool
radioKeyEvent this (KASCII ' ') [] = toggleChecked this >> return True
radioKeyEvent this KEnter [] = toggleChecked this >> return True
radioKeyEvent _ _ _ = return False

setCheckboxUnchecked :: (MonadIO m) => Widget CheckBox -> m ()
setCheckboxUnchecked wRef = setChecked_ wRef False

setCheckboxChecked :: (MonadIO m) => Widget CheckBox -> m ()
setCheckboxChecked wRef = setChecked_ wRef True

toggleChecked :: (MonadIO m) => Widget CheckBox -> m ()
toggleChecked wRef = do
  v <- isChecked <~~ wRef
  setChecked_ wRef (not v)

setChecked_ :: (MonadIO m) => Widget CheckBox -> Bool -> m ()
setChecked_ wRef v = do
  mRg <- radioGroup <~~ wRef

  case mRg of
    Nothing -> setChecked__ wRef v
    Just _ -> case v of
                True -> radioGroupSetCurrent wRef
                -- unchecking a radio button is not permitted except
                -- by the internal API (setChecked__)
                False -> return ()

setChecked__ :: (MonadIO m) => Widget CheckBox -> Bool -> m ()
setChecked__ wRef v = do
  oldVal <- isChecked <~~ wRef

  when (oldVal /= v) $
       do
         updateWidgetState wRef $ \s -> s { isChecked = v }
         notifyChangeHandler wRef

notifyChangeHandler :: (MonadIO m) => Widget CheckBox -> m ()
notifyChangeHandler wRef = do
  h <- checkboxChangeHandler <~~ wRef
  v <- checkboxIsChecked wRef
  liftIO $ h wRef v

checkboxIsChecked :: (MonadIO m) => Widget CheckBox -> m Bool
checkboxIsChecked = (isChecked <~~)

onCheckboxChange :: Widget CheckBox -> (Widget CheckBox -> Bool -> IO ()) -> IO ()
onCheckboxChange wRef handler = do
  oldHandler <- checkboxChangeHandler <~~ wRef

  let combinedHandler =
          \w v -> do
            oldHandler w v
            handler w v

  updateWidgetState wRef $ \s -> s { checkboxChangeHandler = combinedHandler }
