import Control.Exception (try,bracket)
import Control.Monad (forM_) 
import Data.Bytes (Bytes)
import Data.Bytes.Hash (entropy)
import Data.Primitive (ByteArray)
import Data.Word (Word8)
import Hedgehog (Property,Gen,property,forAll,(===),failure,evalIO,annotateShow)
import Hedgehog.Gen (integral,word8,word)
import Hedgehog.Gen (shuffle,list,enumBounded,int,frequency,choice,element)
import Hedgehog.Range (Range,linear)
import Test.Tasty (defaultMain,testGroup,TestTree)
import Test.Tasty.HUnit (testCase,assertEqual,Assertion,(@=?))
import Test.Tasty.Hedgehog (testProperty)
import Control.Monad.IO.Class (liftIO)
import System.IO (openBinaryFile,Handle,IOMode(ReadMode))
import System.IO.Unsafe (unsafePerformIO)
import System.Entropy (CryptHandle,openHandle,closeHandle)

import qualified Data.Bytes as Bytes
import qualified Data.Bytes.Hash as Hash
import qualified Data.Bytes.HashMap as BT
import qualified Data.List as List
import qualified GHC.Exts as Exts

main :: IO ()
main = do
  rand <- openHandle
  defaultMain (tests rand)

tests :: CryptHandle -> TestTree
tests rand = testGroup "bytehash"
  [ testCase "A" (Hash.bytes myEntropy fooBytesA @=? Hash.bytes myEntropy fooBytesB)
  , testCase "B" (Hash.bytes myEntropy fooBytesA @=? Hash.byteArray myEntropy fooByteArray)
  , testCase "C" (Hash.bytes myEntropy mediumBytesA @=? Hash.bytes myEntropy mediumBytesB)
  , testCase "D" (Hash.bytes myEntropy mediumBytesA @=? Hash.byteArray myEntropy mediumByteArray)
  -- , testProperty "small-zero-collisions" smallZeroCollisionsProp
  , testGroup "Map"
    [ testProperty "lookup" byteTableLookupProp
    , testCase "lookup-A" (byteTableLookupA rand) 
    ]
  ]

fooByteArray :: ByteArray
fooByteArray = Bytes.toByteArray (Bytes.fromAsciiString "foo")

fooBytesA :: Bytes
fooBytesA = Bytes.unsafeDrop 1 (Bytes.fromAsciiString "xfoo")

fooBytesB :: Bytes
fooBytesB = Bytes.unsafeDrop 2 (Bytes.fromAsciiString "abfoo")

mediumByteArray :: ByteArray
mediumByteArray = Bytes.toByteArray $ Bytes.fromAsciiString
  "abcdefghijklmnopqrstuvwxyz_now_i_know_my_abcs"

mediumBytesA :: Bytes
mediumBytesA = Bytes.unsafeDrop 1 $ Bytes.fromAsciiString
  "7abcdefghijklmnopqrstuvwxyz_now_i_know_my_abcs"

mediumBytesB :: Bytes
mediumBytesB = Bytes.unsafeDrop 2 $ Bytes.fromAsciiString
  "98abcdefghijklmnopqrstuvwxyz_now_i_know_my_abcs"

myEntropy :: ByteArray
myEntropy = Exts.fromList $ List.take 2000 $ List.cycle
  [ 0x42,0x13,0x12,0x05,0xFF,0x47,0x19,0xE3,0x03,0xFF ]

byteTableLookupProp :: Property
byteTableLookupProp = property $ do
  bytesList <- forAll $ list (linear 0 42) genBytes
  let pairs = map (\x -> (x,x)) bytesList
  case performFromList pairs of
    Left e@(BT.HashMapException{}) -> do
      annotateShow e
      failure
    Right table -> forM_ bytesList $ \bytes -> do
      BT.lookup bytes table === Just bytes

performFromList :: [(Bytes,v)] -> Either BT.HashMapException (BT.Map v)
{-# noinline performFromList #-}
performFromList xs = unsafePerformIO
  $ bracket openHandle closeHandle (\rand -> try (BT.fromList rand xs))

genBytes :: Gen Bytes
genBytes = do
  byteList <- list (linear 0 64) genByte
  front <- genOffset (List.length byteList)
  let raw = Exts.fromList byteList
  if Bytes.length raw >= front
    then return (Bytes.unsafeDrop front raw)
    else error "genBytes: bad"

genByte :: Gen Word8
genByte = word8 (linear minBound maxBound)

genOffset :: Int -> Gen Int
genOffset originalLen = integral (linear 0 maxDiscard)
  where
  maxDiscard = min 19 (div originalLen 3)

byteTableLookupA :: CryptHandle -> IO ()
byteTableLookupA h = do
  let bs :: [(Bytes,Bytes)]
      bs = map (\x -> (Exts.fromList x, Exts.fromList x))
        [ []
        , [0x34,0x36,0x5f,0xe2,0xf3,0x30]
        , [0x7b,0x19,0x08,0xd0,0x0d,0x6b,0xd9,0xa5,0x94,0xc1
          ,0x94,0xf7,0xa7,0x20,0x44,0x45,0x32
          ]
        , [0x28,0xd8,0xeb,0x78,0x7b,0x14,0x3a,0x0d]
        , [0xf3,0xa0,0x02,0xd0]
        ]
  m <- BT.fromList h bs
  forM_ bs $ \(b,_) -> do
    BT.lookup b m @=? Just b
