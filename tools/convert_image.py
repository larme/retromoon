import os, struct, sys
from struct import pack, unpack

def main():
    fname = sys.argv[1]
    cell_num = int(os.path.getsize(fname) / 4)
    with open(fname, 'rb') as f:
        image = list(struct.unpack(cell_num * 'i', f.read()))

    for cell in image:
        print(cell)

if __name__ == '__main__':
    main()
