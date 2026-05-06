-- 09_reset_nn.sql — drop all 1:N:N objects cleanly before each tier

USE bench;

DROP DICTIONARY IF EXISTS order_dict_nn;
DROP TABLE IF EXISTS order_a_nn;
DROP TABLE IF EXISTS purchase_order_a_nn;
DROP TABLE IF EXISTS po_line_a_nn;
DROP TABLE IF EXISTS order_b_nn;
DROP TABLE IF EXISTS purchase_order_b_nn;
DROP TABLE IF EXISTS po_flat_c_nn;
