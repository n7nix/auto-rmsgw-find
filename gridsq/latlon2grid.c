/*
 * Copied this code from here:
 * https://ham.stackexchange.com/questions/221/how-can-one-convert-from-lat-long-to-grid-square
 * Author: Ossi Vaananen
 *
 * Reference:
 * 4829.07       12254.11
 * 48°29.06910', 122°54.11470'
 * 48.4844850°, 122.9019117°
 */

#if 0
#define DEBUG 1
#endif

#include <stdio.h>
#include <stdlib.h>


#ifdef DEBUG
#define pr_debug(format, ...) fprintf (stderr, "DEBUG: "format, ## __VA_ARGS__)
#else
#define pr_debug(format, ...)
#endif

struct s_testdata {
        char *city;
        float lat;
        float lon;
        char *gridsquare;
};

struct s_testdata test_data[8] = {
        { "Munich", 48.14666,11.60833, "JN58td"},
        { "Montevideo", -34.91,-56.21166, "GF15vc"},
        { "Washington, DC", 38.92,-77.065, "FM18lw"},
        { "Wellington", -41.28333,174.745, "RE78ir"},
        { "Newington, CT (W1AW)", 41.714775,-72.727260, "FN31pr"},
        { "Palo Alto (K6WRU)", 37.413708,-122.1073236, "CM87wj"},
        { "Lopez Island", 48.484432,-122.901945, "CN88nl"},
        { NULL, 0, 0, NULL }
};

void calcLocator(char *dst, double lat, double lon);

int main(int argc, char *argv[])
{
        int i;
        float latf, lonf;
        char dst[16];
        dst[0]='\0';

        if (argc < 3) {
                i=0;
                while(test_data[i].city != NULL) {
                        printf("%s ", test_data[i].city);
                        calcLocator(dst, test_data[i].lat, test_data[i].lon);
                        printf("- %s\n", dst);
                        i++;
                }

            exit(0);
        }

        pr_debug("argc=%d, arg 1: %s, arg 2: %s, arg 3: %s\n",
               argc, argv[1], argv[2], argv[3]);
        latf=atof(argv[1]);
        lonf=atof(argv[2]);

        pr_debug("float lat: %f, lon: %f\n", latf, lonf);

        calcLocator(dst, latf, lonf);
        printf("%s\n", dst);
}


void calcLocator(char *dst, double lat, double lon) {
        int o1, o2, o3;
        int a1, a2, a3;
        float adjLon, rLon;
        float adjLat, rLat;

        /* longitude */
        adjLon = lon + 180.0;
        o1 = (int)adjLon/20;
        o2 = (int)(adjLon/2) % 10;

        rLon = (adjLon - 2*(int)(adjLon/2)) * 60;
        o3 = (int)(rLon/5);

        /* latitude */
        adjLat = lat + 90.0;
        a1 = (int)adjLat/10;
        a2 = (int)(adjLat) % 10;

        rLat = (adjLat - (int)(adjLat)) * 60;
        a3 = (int)(rLat/2.5);

        dst[0] = (char)o1 + 'A';
        dst[1] = (char)a1 + 'A';
        dst[2] = (char)o2 + '0';
        dst[3] = (char)a2 + '0';
        dst[4] = (char)o3 + 'a';
        dst[5] = (char)a3 + 'a';
        dst[6] = (char)0;
}
