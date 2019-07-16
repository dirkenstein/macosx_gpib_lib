gcc -o macosx_gpib_lib_1.0.3a.dylib  -dynamiclib -fPIC -framework Foundation -framework IOKit  -include ../macosx_gpib_Prefix.pch -I/usr/local/Cellar/python/3.7.2_2/Frameworks/Python.framework/Versions/3.7/include/python3.7m -L/usr/local/Cellar/python/3.7.2_2/Frameworks/Python.framework/Versions/3.7/lib/ -lpython3.7m *.m *.c
cp macosx_gpib_lib_1.0.3a.dylib ../../
pushd ../../
ln -s macosx_gpib_lib_1.0.3a.dylib gpib.cpython-37m-darwin.so
popd
PYDIR=/usr/local/lib/python3.7/site-packages/
cp gpib.cpython-37m-darwin.so ${PYDIR}

